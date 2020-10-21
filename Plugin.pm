package Plugins::SigGen::Plugin;

# Signal Generator Plugin
#
# (c) Triode - triode1@btinternet.com
#
#

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.siggen',
	'defaultLevel' => 'WARN',
	'description'  => 'PLUGIN_SIGGEN',
});

my $prefs = preferences('server');

use Plugins::SigGen::ProtocolHandler;

# following are the values offered by the menus or remote buttons
my $v = {
	freq => [ 10, 20, 30, 40, 50, 60, 70, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1800,
			  2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000, 12000, 14000, 16000, 18000, 20000 ],
	func => [ 'sine', 'square', 'triangle', 'sawtooth' ],
	amp  => [ -80, -60, -40, -20, -10, -6, 0 ],
	chan => [ 'l+r', 'l', 'r' ],
	bits => [ 16, 24 ],
	rate => [ 8, 11, 12, 16, 22, 24, 32, 44, 48, 88, 96 ],
};

# default signal - indexes into above arrays
my $defaults = {
	freq => 11,
	func => 0,
	chan => 0,
	amp  => 2,
	bits => 0,
	rate => 7,
};

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin;

	Slim::Control::Request::addDispatch(['siggen_menu'], [ 1, 1, 1, \&cliMenu ]);

	my @menu = ({
		stringToken => 'PLUGIN_SIGGEN',
		id          => 'pluginSigGen',
		actions => {
			go => {
				cmd => [ 'siggen_menu' ],
			},
		},
	});

	Slim::Control::Jive::registerPluginMenu(\@menu, 'extras');
}

sub getDisplayName { 'PLUGIN_SIGGEN' };

sub modeName { 'PLUGIN_SIGGEN' };

sub setMode {
	my $class  = shift;
	my $client = shift;

	my $s = $client->pluginData('params') || $defaults;

	$client->pluginData('params', $s);

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

	my $s = $client->pluginData('params');

	return {
		'line'    => [ string('PLUGIN_SIGGEN'), string('PLUGIN_SIGGEN_' . uc $v->{'func'}->[$s->{'func'}]) ],
		'overlay' => [ 
			(sprintf "%s %s/%s", string('PLUGIN_SIGGEN_' . uc $v->{'chan'}->[$s->{'chan'}]), $v->{'rate'}->[$s->{'rate'}], $v->{'bits'}->[$s->{'bits'}]),
			(sprintf "%s dB  %s Hz", $v->{'amp'}->[$s->{'amp'}], $v->{'freq'}->[$s->{'freq'}]),
		],
	};
}

my %functions = (
	'left' => sub { Slim::Buttons::Common::popModeRight(shift) },

	'right'=> sub { shift->bumpRight },

	'up'   => sub {
		my $client = shift;
		my $s = $client->pluginData('params');

		$s->{'freq'} = ($s->{'freq'} + 1) % scalar @{$v->{'freq'}};

		update($client);
	},

	'down' => sub {
		my $client = shift;
		my $s = $client->pluginData('params');

		$s->{'freq'} = ($s->{'freq'} - 1) % scalar @{$v->{'freq'}};

		update($client);
	},

	'numberScroll' => sub {
		my ($client, $funct, $arg) = @_;

		my $s = $client->pluginData('params');

		if ($arg eq '1') {
			$s->{'func'} = ($s->{'func'} + 1) % scalar @{$v->{'func'}};
		}

		if ($arg eq '2') {
			$s->{'amp'} = $s->{'amp'} < scalar @{$v->{'amp'}} - 1 ? $s->{'amp'} + 1 : $s->{'amp'};
		}

		if ($arg eq '3') {
			$s->{'chan'} = ($s->{'chan'} + 1) % scalar @{$v->{'chan'}};
		}

		if ($arg eq '4') {
			$s->{'rate'} = ($s->{'rate'} + 1) % scalar @{$v->{'rate'}};
			if ($v->{'rate'}[$s->{'rate'}] * 1000 > $client->maxSupportedSamplerate) {
				$s->{'rate'} = 0;
			}
		}

		if ($arg eq '5') {
			$s->{'amp'} = $s->{'amp'} > 0 ? $s->{'amp'} - 1 : 0;
		}

		if ($arg eq '6') {
			$s->{'bits'} = ($s->{'bits'} + 1) % scalar @{$v->{'bits'}};
		}

		update($client);
	}
);

sub getFunctions {
	return \%functions;
}

sub update {
	my $client = shift;

	my $s = $client->pluginData('params');

	my $freq = $v->{'freq'}[$s->{'freq'}];
	my $func = $v->{'func'}[$s->{'func'}];
	my $rate = $v->{'rate'}[$s->{'rate'}];
	my $bits = $v->{'bits'}[$s->{'bits'}];
	my $ampL = ($v->{'chan'}[$s->{'chan'}] =~ /l/) ? $v->{'amp'}[$s->{'amp'}] : 'off';
	my $ampR = ($v->{'chan'}[$s->{'chan'}] =~ /r/) ? $v->{'amp'}[$s->{'amp'}] : 'off';

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

sub cliMenu {
	my $request = shift;
	my $client  = $request->client || return;
	my $menu    = $request->getParam('menu') || 'toplevel';
	my $play    = $request->getParam('play');

	my $s = $client->pluginData('params') || $client->pluginData('params', $defaults);

	# handle changes
	my $new;

	for my $param (keys %$v) {

		my $p = $request->getParam($param);

		if (defined $p && $p >= 0 && $p < scalar @{$v->{$param}}) {
			$s->{$param}   = $p;
			$new = 1;
		}
	}

	my $freq = $v->{'freq'}->[$s->{'freq'}];
	my $func = $v->{'func'}->[$s->{'func'}];
	my $rate = $v->{'rate'}->[$s->{'rate'}];
	my $bits = $v->{'bits'}->[$s->{'bits'}];
	my $chan = $v->{'chan'}->[$s->{'chan'}];
	my $amp  = $v->{'amp'}->[$s->{'amp'}];
	my $ampL = ($v->{'chan'}->[$s->{'chan'}] =~ /l/) ? $amp : 'off';
	my $ampR = ($v->{'chan'}->[$s->{'chan'}] =~ /r/) ? $amp : 'off';

	if ($play eq 'stop') {

		$log->info("Stopping");

		$client->execute(['playlist', 'clear']);

		for my $track (Slim::Schema->rs('Track')->search_like({ 'url' => 'siggen%' })->all) {
			$track->delete;
		}

	} elsif ($play eq 'start' || $new) {

		my $url = "siggen://test.raw?func=$func&freq=$freq&rate=$rate&bits=$bits&ampL=$ampL&ampR=$ampR";

		$log->info("Playing $url");

		Slim::Music::Info::setTitle($url, "$freq Hz " . string("PLUGIN_SIGGEN_$func") . " $amp dB " .
										  string("PLUGIN_SIGGEN_$chan") . " $rate/$bits" );

		$client->execute(['playlist', 'play', $url]);
	}

	# build new menu

	my @menu = ();
	my $title;

	if ($menu eq 'toplevel') {

		push @menu, {
			text       => $client->isPlaying ? string('PLUGIN_SIGGEN_STOP') : string('PLUGIN_SIGGEN_STOPPED'),
			actions    => { go => { cmd => ['siggen_menu'], params => { play => $client->isPlaying ? 'stop' : 'start' } } },
			nextWindow => 'refresh',
		};

		my @menus = (freq => sprintf(string('PLUGIN_SIGGEN_FREQUENCY'), $freq),
					 amp  => sprintf(string('PLUGIN_SIGGEN_AMPLITUDE'), $amp),
					 func => sprintf(string('PLUGIN_SIGGEN_FUNCTION'),  string("PLUGIN_SIGGEN_$func")),
					 chan => sprintf(string('PLUGIN_SIGGEN_CHANNEL'),   string("PLUGIN_SIGGEN_$chan")),
					 rate => sprintf(string('PLUGIN_SIGGEN_RATE'),      $rate),
					 bits => sprintf(string('PLUGIN_SIGGEN_BITS'),      $bits),
					);

		while (my ($key, $text) = splice @menus, 0, 2) {
			push @menu, {
				text    => $text,
				actions => { go => { cmd => [ 'siggen_menu' ], params => { menu => $key } } },
			};
		}

	} if ($menu && exists $v->{$menu}) {

		$title = string('PLUGIN_SIGGEN_TITLE_' . $menu);

		my $text = {
			freq => sub { $_[0] . " Hz" },
			amp  => sub { $_[0] . " dB" },
			func => sub { string("PLUGIN_SIGGEN_" . $_[0]) },
			chan => sub { string("PLUGIN_SIGGEN_" . $_[0]) },
			rate => sub { $_[0] . " kHz" },
			bits => sub { $_[0] } ,
		};

		for my $i (0 .. scalar @{$v->{$menu}} - 1) {
			push @menu, {
				text    => $text->{$menu}->($v->{$menu}->[$i]),
				radio   => $s->{$menu} == $i ? 1 : 0,
				actions => { do => { cmd => ['siggen_menu'], params => { $menu => $i } } },
				nextWindow => 'refreshOrigin',
			};
		}
	}

	if ($title) {
		$request->addResult('window', { text => $title });
	}

	$request->addResult('count', scalar @menu);
	$request->addResult('offset', 0);

	my $cnt = 0;

	for my $item (@menu) {
		$request->setResultLoopHash('item_loop', $cnt++, $item);
	}

	$request->setStatusDone;
}


1;
