unit class ISP::Servers:api<1>:auth<Mark Devine (mark@markdevine.com)>;

use Terminal::ANSIColor;
use Term::Choose;

has %.isp-servers;

class ISP-SERVER-INFO {
    has $.TCPSERVERADDRESS  is rw;
}

constant $isp-server-REDIS-keys-base  = 'eb:isp:servers';

submethod TWEAK {
    my @redis-servers;
    if "$*HOME/.redis-servers".IO.f {
        @redis-servers = slurp("$*HOME/.redis-servers").chomp.split("\n");
    }
    else {
        die 'Unable to initialized without ~/.redis-servers';
    }
    my @redis-clis;
    for @redis-servers -> $redis-server {
        my @cmd-string = sprintf("ssh -L 127.0.0.1:6379:%s:6379 %s /usr/bin/redis-cli", $redis-server, $redis-server).split: /\s+/;
        @redis-clis.push: @cmd-string;
    }
    for @redis-clis -> @redis-cli {
        my @rcmd        = flat @redis-cli,
                        '--raw',
                        'KEYS',
                        $isp-server-REDIS-keys-base ~ ':*';
        my $proc        = run   @rcmd, :out, :err;
        my $out         = $proc.out.slurp(:close);
        my $err         = $proc.err.slurp(:close);
        fail 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
        if $out {
            my @ispssks = $out.chomp.split("\n");
            die "No ISP server site keys!" unless @ispssks;
            @rcmd   = flat @redis-cli,
                    '--raw',
                    'SUNION',
                    @ispssks.join: ' ';
            $proc    = run   @rcmd, :out, :err;
            $out     = $proc.out.slurp(:close);
            $err     = $proc.err.slurp(:close);
            die 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
            if $out {
                %!isp-servers = $out.chomp.split("\n").map: { $_.uc => 0 };
                die "Set up '/opt/tivoli/tsm/client/ba/bin/dsm.sys' & install '/usr/bin/dsmadmc' on this host." unless '/opt/tivoli/tsm/client/ba/bin/dsm.sys'.IO.path:s;
                my @dsm-sys     = slurp('/opt/tivoli/tsm/client/ba/bin/dsm.sys').lines;
                my $current-server;
                my $current-client;
                for @dsm-sys -> $rcd {
                    if $rcd ~~ m:i/ ^ SERVERNAME \s+ $<client>=(<alnum>+?) '_' $<server>=(<alnum>+) \s* $ / {           # %%% make this accept client names with '_'; take all but not the last '_'
                        $current-server = $/<server>.Str;
                        $current-client = $/<client>.Str;
                        %!isp-servers{$current-server}{$client} .= ISP-SERVER-INFO.new(:SERVERNAME($/<client>.Str ~ '_' ~ $current-server));
                    }
                    elsif $rcd ~~ m:i/ ^ \s* TCPS\w* \s+ $<value>=(.+) \s* $/ {
                        %!isp-servers{$current-server}{$current-client}.TCPSERVERADDRESS = $/<value>.Str;
                    }
                }
                return self;
            }
        }
    }
    unless %!isp-servers.elems {
        $*ERR.put: colored('No ISP Servers defined in Redis under ' ~ $isp-server-REDIS-keys-base ~ ' keys!', 'red');
        die colored('Either fix your --$isp-server=<value> or update Redis ' ~ $isp-server-REDIS-keys-base ~ ':*', 'red');
    }
}

method isp-server (Str $isp-server-name?) {
    my $isp-server;
    $isp-server = $isp-server-name if $isp-server-name;
    if $isp-server {
        $isp-server = $isp-server.uc;
        return $isp-server if  %!isp-servers{$isp-server}:exists;
        die 'Unknown ISP server specified <' ~ $isp-server ~ '>!';
    }
    if $*OUT.t {
        my $tc = Term::Choose.new( :0mouse, :0order );
        until $isp-server {
            $isp-server = $tc.choose(%!isp-servers.keys.sort, :0clear-screen, :2layout, :0default);
        }
        return $isp-server;
    }
    else {
        die 'Cannot select an ISP server non-interactively!';
    }
    die;
}

method SERVERNAME (Str:D :$isp-server, Str:D :$isp-client) {
    die "Invalid ISP Server name <' ~ $isp-server ~ '> specified!'  unless %!isp-servers{$isp-server}:exists;
    die "Invalid ISP client name <' ~ $isp-client ~ '> specified!'  unless %!isp-servers{$isp-server}{$isp-client}:exists;
    return %!isp-servers{$isp-server}{$isp-client}.SERVERNAME if %!isp-servers{$isp-server-name}{$isp-client}.SERVERNAME;
    $*ERR.put: colored('No SERVERNAME stanza associated with ISP client <' ~ $isp-client ~ '> and ISP server <' ~ $isp-server ~ '>!', 'red');
    die "Set up '/opt/tivoli/tsm/client/ba/bin/dsm.sys' & /usr/bin/dsmadmc before using this script with a "SERVERNAME ' ~ $isp-client ~ '_' ~ $isp-server ~ '" stanza before proceeding.';
}

=finish
