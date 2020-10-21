package Plugins::SigGen::Plugin;

# Signal Generator Plugin

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

use Plugins::SigGen::ProtocolHandler;

sub getDisplayName { 'PLUGIN_SIGGEN' };

sub modeName { 'PLUGIN_SIGGEN' };

my $prefs = preferences('server');

# following are the setting which are changed from the remote with button presses
my @funcs = ( 'sine', 'square', 'triangle', 'sawtooth' );  # button 1
my @amps  = ( -80, -60, -40, -20, -10, -6, 0 );            # button 2 inc, button 5 dec
my @chans = ( 'l+r', 'l', 'r' );                           # button 3
my @bits  = ( 16, 24 );                                    # button 4
my @rates = ( 8, 11, 12, 16, 22, 24, 32, 44, 48, 88, 96 ); # button 6

sub setMode {
	my $class  = shift;
	my $client = shift;

	my $s = $client->modeParam('params') || {
		'freq'   => 500,
		'func'   => 0,
		'chan'   => 0,
		'amp'    => 2,
		'bits'   => 0,
		'rate'   => 7,
	};

	$client->modeParam('params', $s);

	$client->lines(\&lines);

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time + 1.0, \&update);

	avoidScreenSaver($client);
}

sub exitMode {
	my $class  = shift;
	my $client = shift;

	$client->execute(['playlist', 'clear']);

	for my $track (Slim::Schema->rs('Track')->search_like({ 'url' => 'siggen%' })->all) {
		$track->delete;
	}

	$client->display->updateMode(0);
}

sub lines {
	my $client = shift;

	my $s = $client->modeParam('params');

	return {
		'line'    => [ string('PLUGIN_SIGGEN'), string('PLUGIN_SIGGEN_' . uc $funcs[$s->{'func'}]) ],
		'overlay' => [ 
			(sprintf "%s %s/%s", string('PLUGIN_SIGGEN_' . uc $chans[$s->{'chan'}]), $rates[$s->{'rate'}], $bits[$s->{'bits'}]),
			(sprintf "%s dB  %s Hz", $amps[$s->{'amp'}], $s->{'freq'}),
		],
	};
}

my %functions = (
	'left' => sub { Slim::Buttons::Common::popModeRight(shift) },

	'right'=> sub { shift->bumpRight },

	'up'   => sub {
		my $client = shift;
		my $s = $client->modeParam('params');

		if ($s->{'freq'} < 20000) {

			$s->{'freq'} += ($s->{'freq'} >= 100 ? 100 : 10);

			update($client);
		}
	},

	'down' => sub {
		my $client = shift;
		my $s = $client->modeParam('params');

		if ($s->{'freq'} > 10) {

			$s->{'freq'} -= ($s->{'freq'} > 100 ? 100 : 10);

			update($client);
		}
	},

	'jump'  => sub {
		my ($client, $funct, $arg) = @_;
		my $s = $client->modeParam('params');

		if ($arg eq 'rew') {
			$s->{'freq'} = $s->{'freq'} > 100 ? $s->{'freq'} / 10 : $s->{'freq'};
		}

		if ($arg eq 'fwd') {
			$s->{'freq'} = $s->{'freq'} <= 2000 ? $s->{'freq'} * 10 : $s->{'freq'};
		}

		update($client);
	},

	'numberScroll' => sub {
		my ($client, $funct, $arg) = @_;

		my $s = $client->modeParam('params');

		if ($arg eq '1') {
			$s->{'func'} = ($s->{'func'} + 1) % scalar @funcs;
		}

		if ($arg eq '2') {
			$s->{'amp'} = $s->{'amp'} < $#amps ? $s->{'amp'} + 1 : $s->{'amp'};
		}

		if ($arg eq '3') {
			$s->{'chan'} = ($s->{'chan'} + 1) % scalar @chans;
		}

		if ($arg eq '4') {
			$s->{'rate'} = ($s->{'rate'} + 1) % scalar @rates;
			if ($rates[$s->{'rate'}] * 1000 > $client->maxSupportedSamplerate) {
				$s->{'rate'} = 0;
			}
		}

		if ($arg eq '5') {
			$s->{'amp'} = $s->{'amp'} > 0 ? $s->{'amp'} - 1 : 0;
		}

		if ($arg eq '6') {
			$s->{'bits'} = ($s->{'bits'} + 1) % scalar @bits;
		}

		update($client);
	}
);

sub getFunctions {
	return \%functions;
}

sub update {
	my $client = shift;

	my $s = $client->modeParam('params');

	my $freq = $s->{'freq'};
	my $func = $funcs[$s->{'func'}];
	my $rate = $rates[$s->{'rate'}];
	my $bits = $bits[$s->{'bits'}];
	my $ampL = ($chans[$s->{'chan'}] =~ /l/) ? $amps[$s->{'amp'}] : 'off';
	my $ampR = ($chans[$s->{'chan'}] =~ /r/) ? $amps[$s->{'amp'}] : 'off';

	my $url = "siggen://test.raw?func=$func&freq=$freq&rate=$rate&bits=$bits&ampL=$ampL&ampR=$ampR";

	Slim::Music::Info::setTitle($url, string('PLUGIN_SIGGEN_TESTSIGNAL') ." $func $freq Hz");

	$client->display->updateMode(1);
	$client->showBriefly(lines($client), { 'duration' => 3, 'block' => 1 });

	Slim::Utils::Timers::killTimers($client, \&execute);
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.5, \&execute, $url);
}

sub execute {
	my $client = shift;
	my $url    = shift;

	$client->execute(['playlist', 'play', $url]);
}

sub avoidScreenSaver {
	my $client = shift;

	my $now     = Time::HiRes::time();
	my $timeout = $prefs->client($client)->get('screensavertimeout') || return;

	if (Slim::Buttons::Common::mode($client) eq 'PLUGIN_SIGGEN') {

		if ($now - Slim::Hardware::IR::lastIRTime($client) > $timeout / 2) {
			Slim::Hardware::IR::setLastIRTime($client, $now);
		}

		Slim::Utils::Timers::setTimer($client, $now + $timeout / 2, \&avoidScreenSaver);
	}
}

1;
