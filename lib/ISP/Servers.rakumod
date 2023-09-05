unit class ISP::Servers:api<1>:auth<Mark Devine (mark@markdevine.com)>;

use Term::Choose;

has %.isp-servers;

class ISP-SERVER-INFO {
    has $.CLIENT;
    has $.SERVERNAME;
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
            fail 'FAILED: ' ~ @rcmd ~ ":\t" ~ $err if $err;
            if $out {
                %!isp-servers = $out.chomp.split("\n").map: { $_.uc => 0 };
                die "Set up '/opt/tivoli/tsm/client/ba/bin/dsm.sys' & install '/usr/bin/dsmadmc' on this host." unless '/opt/tivoli/tsm/client/ba/bin/dsm.sys'.IO.path:s;
                my @dsm-sys     = slurp('/opt/tivoli/tsm/client/ba/bin/dsm.sys').lines;
                my $current-server;
                for @dsm-sys -> $rcd {
                    if $rcd ~~ m:i/ ^ SERVERNAME \s+ $<client>=(<alnum>+?) '_' $<server>=(<alnum>+) \s* $ / {           # %%% make this accept client names with '_'; take all but not the last '_'
                        $current-server = $/<server>.Str;
                        %!isp-servers{$current-server} .= ISP-SERVER-INFO.new(:CLIENT($/<client>.Str), :SERVERNAME($/<client>.Str ~ '_' ~ $current-server));
                    }
                    elsif $rcd ~~ m:i/ ^ \s* TCPS\w* \s+ $<value>=(.+) \s* $/ {
                        %!isp-servers{$current-server}.TCPSERVERADDRESS = $/<value>.Str;
                    }
                }
                return self;
            }
        }
    }
    die 'No ISP Servers defined in Redis under ' ~ $isp-server-REDIS-keys-base ~ ' keys!' unless %!isp-servers.elems;
}

method isp-server (Str $isp-server-name?) {
    my $isp-server;
    $isp-server = $isp-server-name if $isp-server-name;
    if $isp-server {
        $isp-server = $isp-server.uc;
        die "Unknown ISP server specified!" unless %!isp-servers{$isp-server}:exists;
        return(%!isp-servers{$isp-server}.SERVERNAME) if %!isp-servers{$isp-server}.SERVERNAME;
        die "Set up '/opt/tivoli/tsm/client/ba/bin/dsm.sys' with the appropriate SERVERNAME stanza.";
    }
    else {
        if $*OUT.t {
            my $tc = Term::Choose.new( :0mouse, :0order );
            until $isp-server {
                $isp-server = $tc.choose(%!isp-servers.keys.sort, :0clear-screen, :2layout, :0default);
            }
        }
        else {
            die 'Cannot select an ISP server non-interactively!';
        }
        return $isp-server;
    }
    die;
}


=finish

    unless %stanzas{$PRIMARY_SERVER_NAME}:exists {
        warn "Use any of:"
        .warn for %stanzas.keys;
        die 'SERVERNAME stanza containing $isp-server <' ~ $PRIMARY_SERVER_NAME ~ "> not found in '/opt/tivoli/tsm/client/ba/bin/dsm.sys'";
    }

