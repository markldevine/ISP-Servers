unit class ISP::Servers:api<1>:auth<Mark Devine (mark@markdevine.com)>;

use Term::Choose;

has @.isp-servers;

constant $isp-server-keys-base  = 'eb:isp:servers';

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
    my %isp-servers;
    for @redis-clis -> @redis-cli {
        my @rcmd        = flat @redis-cli,
                        '--raw',
                        'KEYS',
                        $isp-server-keys-base ~ ':*';
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
            fail 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
            if $out {
                %isp-servers = $out.chomp.split("\n").map: { $_.uc => 0 };
                for %isp-servers.keys.sort -> $isps {
                    @!isp-servers.push: $isps;
                }
                return(@!isp-servers);
            }
        }
    }
    die 'No ISP Servers defined in Redis under ' ~ $isp-server-keys-base ~ ' keys!' unless @!isp-servers.elems;
}

method isp-server (Str $isp-server-name?) {
    my $isp-server;
    $isp-server = $isp-server-name if $isp-server-name;
    if $isp-server {
        $isp-server = $isp-server.uc;
        for @!isp-servers -> $isp-server-name {
            return($isp-server) if $isp-server eq $isp-server-name;
        }
        return Nil;
    }
    else {
        $isp-server = @!isp-servers[0] if @!isp-servers.elems == 1;
        unless $isp-server {
            if $*OUT.t {
                my $tc = Term::Choose.new( :0mouse, :0order );
                until $isp-server {
                    $isp-server = $tc.choose(@!isp-servers, :0clear-screen, :2layout, :0default);
                }
            }
            else {
                die 'Cannot select an ISP server non-interactively!';
            }
        }
    }
    return $isp-server;
}


=finish

################################################################################
#   Sort out the ISP server info                                               #
################################################################################

    my $PRIMARY_SERVER_NAME = $isp-server.uc;
    unless %isp-servers{$PRIMARY_SERVER_NAME}:exists {
        $*ERR.put: colored('Unrecognized $isp-server <' ~ $isp-server ~ '> specified!', 'red');
        die colored('Either fix your --$isp-server=<value> or update Redis eb:isp:servers:*', 'red');
    }
    die "Set up '/opt/tivoli/tsm/client/ba/bin/dsm.sys' & /usr/bin/dsmadmc on this host platform before using this script." unless '/opt/tivoli/tsm/client/ba/bin/dsm.sys'.IO.path:s;
    my @dsm-sys     = slurp('/opt/tivoli/tsm/client/ba/bin/dsm.sys').lines;
    my %stanzas;
    my $current-key = 'ERROR';
    for @dsm-sys -> $rcd {
        if $rcd ~~ m:i/ ^ SERVERNAME \s+ <alnum>+? '_' $<server>=(<alnum>+) \s* $ / {
            $current-key = $/<server>.Str;
            next;
        }
        elsif $rcd ~~ m:i/ ^ \s* TCPS\w* \s+ $<value>=(.+) \s* $/ {
            %stanzas{$current-key}<TCPSERVERADDRESS> = $/<value>.Str;
        }
    }
    unless %stanzas{$PRIMARY_SERVER_NAME}:exists {
        warn "Use any of:"
        .warn for %stanzas.keys;
        die 'SERVERNAME stanza containing $isp-server <' ~ $PRIMARY_SERVER_NAME ~ "> not found in '/opt/tivoli/tsm/client/ba/bin/dsm.sys'";
    }

