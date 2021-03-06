use strict;
use warnings;
use English;
use Test::More;

plan tests => 15;

my $maxage = 60*60*24;  # 1 day

sub get_utc_time {
    my $t = shift || time;
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
        gmtime($t);
    $year += 1900;
    $mon++;
    my $time;
    my $microseconds = 0;
    eval { # if Time::HiRes is available, use it to get microseconds
        use Time::HiRes qw( gettimeofday );
        my ($seconds, $micro) = gettimeofday();
        $microseconds = $micro;
    };
    $time = sprintf("%04d%02d%02d%02d%02d%02d%06d", $year, $mon, $mday, $hour, $min, $sec, $microseconds);

    return $time;
}

use OpenXPKI::Debug;
if ($ENV{DEBUG_LEVEL}) {
    $OpenXPKI::Debug::LEVEL{'.*'} = $ENV{DEBUG_LEVEL};
}


our $dbi;
our $token;
require 't/30_dbi/common.pl';

use OpenXPKI::Server::Context;
use OpenXPKI::Server::Log;

OpenXPKI::Server::Context::setcontext({
    dbi_log => $dbi,
    dbi_backend => $dbi
});
my $log = OpenXPKI::Server::Log->new( CONFIG => 't/30_dbi/log4perl.conf' );

my $wf_id = int(rand(10000000));
my $msg = sprintf "DBI Log Workflow Test %01d", rand(10000000);
OpenXPKI::Server::Context::setcontext({
    workflow_id => $wf_id 
});

ok ($log->log (FACILITY => "application",
               PRIORITY => "info",
               MESSAGE  => $msg), 'Workflow Test message')
           or diag "ERROR: log=$log";

my $result = $dbi->select(
    TABLE => 'APPLICATION_LOG',
    DYNAMIC => 
    {
        CATEGORY => {VALUE => 'openxpki.application' },
        MESSAGE => {VALUE => "%$msg", OPERATOR => 'LIKE'},
    }
);
is(scalar @{$result}, 1, "Log entry found: $msg");

my $serial = $dbi->get_new_serial(TABLE => 'APPLICATION_LOG');
$msg = sprintf "DBI Log Workflow Test Old %01d", rand(10000000);
my $timestamp = get_utc_time( time - $maxage + 5);
#diag "WFID=$wf_id, TS=$timestamp, SER=$serial, MSG=$msg";
isnt($serial, 0, 'serial for test entry not zero') or die "Error: unable to continue without serial";
ok($dbi->insert(
        TABLE => 'APPLICATION_LOG',
        HASH => {
            APPLICATION_LOG_SERIAL => $serial,
            TIMESTAMP => $timestamp,
            WORKFLOW_SERIAL => $wf_id,
            CATEGORY => 'openxpki.application',
            PRIORITY => 'info',
            MESSAGE => $msg,
        },
    ), "insert old test message");
ok($dbi->commit(), "Commit insert of old test message");

$serial = $dbi->get_new_serial(TABLE => 'APPLICATION_LOG');
$msg = sprintf "DBI Log Workflow Test Old %01d", rand(10000000);
$timestamp = get_utc_time( time - $maxage - 5);
#diag "WFID=$wf_id, TS=$timestamp, SER=$serial, MSG=$msg";
isnt($serial, 0, 'serial for test entry not zero') or die "Error: unable to continue without serial";
ok($dbi->insert(
        TABLE => 'APPLICATION_LOG',
        HASH => {
            APPLICATION_LOG_SERIAL => $serial,
            TIMESTAMP => $timestamp,
            WORKFLOW_SERIAL => $wf_id,
            CATEGORY => 'openxpki.application',
            PRIORITY => 'info',
            MESSAGE => $msg,
        },
    ), "insert old test message");
ok($dbi->commit(), "Commit insert of old test message");

$result = $dbi->select(
    TABLE => 'APPLICATION_LOG',
    DYNAMIC => 
    {
        CATEGORY => {VALUE => 'openxpki.application' },
        WORKFLOW_SERIAL => {VALUE => $wf_id, OPERATOR => 'EQUAL'},
    }
);
is(scalar @{$result}, 3, "Log entries found for WFID $wf_id");

# CALL API TO PURGE RECORDS
my $maxutc = get_utc_time( time - $maxage );
ok(CTX('api')->purge_application_log( { MAXAGE => $maxage } ), "exec purge_application_log for $maxutc");

$result = $dbi->select(
    TABLE => 'APPLICATION_LOG',
    DYNAMIC => 
    {
        CATEGORY => {VALUE => 'openxpki.application' },
        WORKFLOW_SERIAL => {VALUE => $wf_id, OPERATOR => 'EQUAL'},
    }
);
is(scalar @{$result}, 2, "2 log entries found for WFID $wf_id after purge");

1;
