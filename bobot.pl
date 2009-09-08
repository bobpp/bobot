#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  bobot.pl
#        USAGE:  ./bobot.pl  
#
#       AUTHOR:  bobpp < bobpp.asroma+github@gmail.com >
#      VERSION:  1.0
#      CREATED:  08/30/2009 04:19:53 PM
#===============================================================================

use strict;
use warnings;
use utf8;
use File::Spec;
use YAML;
use Net::IRC;
use DBI;
use Time::Local;

my $config_file_path = shift;
my $config = YAML::LoadFile(File::Spec->catfile($config_file_path));

my $i = new Net::IRC;
my $conn = $i->newconn(
	Nick     => $config->{nick},
	Server   => $config->{server},
	Port     => $config->{port},
	Ircname  => $config->{nick},
	Username => $config->{nick},
);

my $dbh = DBI->connect("dbi:SQLite:dbname=bobot.sqlite3", "", "", {AutoCommit => 1});

# for karma
my $karma_exists_sth = $dbh->prepare(<<'SQL');
	SELECT id FROM karma WHERE channel = ? AND name = ?
SQL
my $karma_initialize_sth = $dbh->prepare(<<'SQL');
	INSERT INTO karma (channel, name) VALUES (?, ?)
SQL
my $karma_plus_sth = $dbh->prepare(<<'SQL');
	UPDATE karma SET total = total+1, plus = plus+1 WHERE channel = ? AND name = ?
SQL
my $karma_minus_sth = $dbh->prepare(<<'SQL');
	UPDATE karma SET total = total-1, minus = minus+1 WHERE channel = ? AND name = ?
SQL
my $karma_check_sth = $dbh->prepare(<<'SQL');
	SELECT total, plus, minus FROM karma WHERE channel = ? AND name = ?
SQL

# for msgs
my $msg_check_sth = $dbh->prepare(<<'SQL');
	SELECT from_name, body FROM msg WHERE channel = ? AND to_name = ?
SQL
my $set_msg_sth = $dbh->prepare(<<'SQL');
	INSERT INTO msg (channel, from_name, to_name, body) VALUES (?, ?, ?, ?)
SQL
my $del_msg_sth = $dbh->prepare(<<'SQL');
	DELETE FROM msg WHERE channel = ? AND to_name = ?
SQL

# 時報
my $timer_check_sth = $dbh->prepare(<<'SQL');
	SELECT id, body FROM timer WHERE channel = ? AND hour = ? AND minute = ? AND last_sent < ?
SQL
my $timer_set_sth = $dbh->prepare(<<'SQL');
	INSERT INTO timer (channel, hour, minute, body) VALUES (?, ?, ?, ?)
SQL
my $timer_sent_sth = $dbh->prepare(<<'SQL');
	UPDATE timer SET last_sent = ? WHERE id = ?
SQL

# help msg
my $help_msg = <<EOH;
(\\w+)(++|--) : 投票
  ex: bobpp++, hogefuga--
vote (\\w+) : 投票結果を見る
  ex: vote bobpp
msg (\\w+) <msg> : (\\w+)さんに伝言する (次回 join 時に発言します)
  ex: msg bobpp 明日のみにいこうよ
timer (\\d{2}:\\d{2}) <msg> : (\\d{2}:\\d{2})に <msg> を時報としてセットする
  ex: timer 12:00 ご飯の時間ですよ
EOH

sub show_karma {
	my ($irc, $c, $n) = @_;

	$karma_check_sth->execute($c, $n);
	my ($total, $plus, $minus) = $karma_check_sth->fetchrow_array;
	$total ||= 0;
	$plus  ||= 0;
	$minus ||= 0;
	$irc->notice($c, "$n => $total (++:$plus, --:$minus)");
}

# 発言に関する
$conn->add_handler('public', sub {
	my ($self, $e) = @_;

	my $channel = $e->{to}[0];
	my $msg = $e->{args}[0];

	# karma
	if ($msg =~ /(\w+)(\+\+|\-\-)/) {
		$karma_exists_sth->execute($channel, $1);
		unless (my ($id) = $karma_exists_sth->fetchrow_array) {
			$karma_initialize_sth->execute($channel, $1);
		}

		my $karma_change_sth = ($2 eq '++') ? $karma_plus_sth : $karma_minus_sth;
		$karma_change_sth->execute($channel, $1);

		show_karma($self, $channel, $1);
	}

	# karma check
	if ($msg =~ /^vote (\w+)$/) {
		show_karma($self, $channel, $1);
	}

	# msg
	if ($msg =~ /^msg (\w+) (.*)$/) {
		$set_msg_sth->execute($channel, $e->{nick}, $1, $2);
		$self->notice($channel, "Message set OK");
	}

	# 時報
	if ($msg =~ /^timer (\d{2}):(\d{2}) (.*)$/) {
		$timer_set_sth->execute($channel, $1, $2, $3);
		$self->notice($channel, "Timer set OK");
	}

	# help, misc...
	if ($msg =~ /^bobot: (\w+)$/) {
		if ($1 eq 'help') {
			$self->notice($channel, $_) for split /\n/, $help_msg;
		}
	}
});

# Join に関する
$conn->add_handler('join', sub {
	my ($self, $e) = @_;

	my $channel = $e->{to}[0];
	my $nick = $e->{nick};

	# msg
	$msg_check_sth->execute($channel, $nick);
	my @messages;
	while (my ($f, $m) = $msg_check_sth->fetchrow_array) {
		push @messages, "From:$f / $m";
	}
	if (scalar @messages) {
		$self->privmsg($channel, "Welcome $nick メッセージがあるよ");
		$self->notice($channel, $_) for @messages;
	}
	$del_msg_sth->execute($channel, $nick);
});

# 30sec ごと
sub timer_tick {
	my ($self, $e) = @_;

	# 時報
	for my $channel (@{$config->{channels}}) {
		$timer_check_sth->execute($channel, (localtime)[2,1], time - 120);
		while (my ($id, $msg) = $timer_check_sth->fetchrow_array) {
			$self->notice($channel, "Timer: $msg");
			$timer_sent_sth->execute(time, $id);
		}
	}
	$self->schedule(30, \&timer_tick);
}
$conn->schedule(0, \&timer_tick);

$conn->join($_) for (@{$config->{channels}});
$i->start;

