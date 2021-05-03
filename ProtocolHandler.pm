package Plugins::SigGen::ProtocolHandler;

use strict;

use base qw(IO::Handle);

use Slim::Utils::Log;

my $log = logger('plugin.siggen');

use bytes;

my $rates = {
	 '8' =>  8000,
	'11' => 11025,
	'12' => 12000,
	'16' => 16000,
	'22' => 22050,
	'32' => 32000,
	'44' => 44100,
	'48' => 48000,
	'88' => 88200,
	'96' => 96000,
};

use constant TWO_PI => 8 * atan2(1, 1);

# following define the functions that we can can generate signals for
# called with $_[0] = sample number, $_[1] = period in samples
my $functions = {
	'sine'     => sub { sin( TWO_PI * ($_[0] % $_[1]) / $_[1] ) },
	'square'   => sub { ($_[0] % $_[1] >= $_[1] / 2) ? 1 : -1   },
	'triangle' => sub { ($_[0] % $_[1] >= $_[1] / 2) ? 3 - 4 * ($_[0] % $_[1]) / $_[1] : -1 + 4 * ($_[0] % $_[1]) / $_[1] },
	'sawtooth' => sub { 2 * ($_[0] % $_[1]) / $_[1] - 1 },
	'silence'  => sub { 0 },
};

Slim::Player::ProtocolHandlers->registerHandler('siggen', __PACKAGE__);

# accept urls of the form: siggen://test.raw?func=sine&freq=1000&rate=96&bits=24&ampL=0&ampR=0

sub new {
	my $class = shift;
	my $args = shift;

	my $self = $class->SUPER::new;

	my $url    = $args->{'url'};
	my $client = $args->{'client'};

	unless ($url =~ /siggen:\/\/test.raw/) {
		$log->warn("bad url: $url");
		return undef;
	}

	$log->info("url: $url");

	my ($query) = $url =~ /\?(.*)/;

	my $params = {};

	for my $param (split /\&/, $query) {
		my ($key, $value) = $param =~ /(.*)=(.*)/;
		$params->{ $key } = $value;
	}

	my $func = $functions->{ $params->{'func'} || 'silence' };
	my $freq = $params->{'freq'} || 1000;
	my $rate = $rates->{ $params->{'rate'} } || 44100;
	my $bits = $params->{'bits'} && $params->{'bits'} == 24 ? 24 : 16;

	my $max  = $bits == 16 ? 0x7fff : 0x7fffff;

	my $ampL = !exists $params->{'ampL'} || $params->{'ampL'} eq 'off' ? 0 : exp( $params->{'ampL'} / 20 * log(10) ) * $max;
	my $ampR = !exists $params->{'ampR'} || $params->{'ampR'} eq 'off' ? 0 : exp( $params->{'ampR'} / 20 * log(10) ) * $max;

	$log->info("freq: $freq function: $params->{'func'} $rate/$bits left: $ampL right: $ampR");

	my $period  = int (($rate / $freq) + 0.5);

	$log->info("period: $period actual freq: " . $rate / $period . " Hz");

	# length of buffer is an integral number of sample periods to avoid joins when it is repeated
	my $samples = int(Slim::Web::HTTP::MAXCHUNKSIZE / ($bits/4)) - int(Slim::Web::HTTP::MAXCHUNKSIZE / ($bits/4)) % $period;

	my $buf = '';

	for (my $s = 0; $s < $samples; $s++) {

		my $val = &$func($s, $period);

		if ($bits == 16) {
			# 16 bits
			$buf .= pack "ss", $ampL * $val, $ampR * $val;

		} else {
			# 24 bits
			my $valL = ($val * $ampL) & 0xffffff;
			my $valR = ($val * $ampR) & 0xffffff;

			$buf .=
				chr ($valL & 0xff) . chr (($valL >> 8) & 0xff) . chr (($valL >> 16) & 0xff) .
				chr ($valR & 0xff) . chr (($valR >> 8) & 0xff) . chr (($valR >> 16) & 0xff) ;
		}
	}

	$log->debug("created buffer containing $samples samples, length: " . length $buf);

	${*$self}{'buf'} = $buf;

	# we need to store the sample rate and size in the database
	my $track = Slim::Schema->rs('Track')->objectForUrl({
		'url' => $url,
	});

	$track->samplesize($bits);
	$track->samplerate($rate);
	$track->update;

	return $self;
}

sub getMetadataFor {
	my ( $class, $client, $url, $forceCurrent ) = @_;

	my $icon = Plugins::SigGen::Plugin->_pluginDataFor('icon');

	return {
		icon => $icon,
		cover => $icon,
		bitrate => '',
	};
}

# this handles streaming of the buffer to the player - just send the whole buffer each time
sub sysread {
	my $self = $_[0];

	$_[1] = ${*$self}{'buf'};

	return length $_[1];
}

sub isRemote { 0 }

sub contentType { 'raw' }

1;
