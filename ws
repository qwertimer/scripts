#!/usr/bin/env perl
#          ^^^ only because this is a rapid prototype

# This is an unoptimized prototype with lots of subshells in preparation
# for port to Go eventually. In other words, this just works for now.
# See documentation after __END__ at the bottom. (I didn't feel like
# writing it in Perl POD format, sorry.)

use v5.14;
use File::Path qw(make_path);
no strict;

for (qw( yq docker id )) {
    not `which $_` and say "Missing dependency: $_" and exit 1;
}

# attemp to filter out that piece of shit Python yq
`yq --help` =~ /eval-all.*shell-completion/s or say "Missing GOOD yq." and exit 1;

my $wsdir  = $ENV{'WORKSPACES'}      || "$ENV{'HOME'}/Workspaces";
my $image  = image() || $ENV{'WORKSPACE_IMAGE'} || 'rwxrob/workspace';
my $editor = $ENV{'EDITOR'}          || 'vi';

not -d $wsdir and mkdir($wsdir);

sub end {
    say shift;
    exit;
}

sub get_ws_list {
    opendir( my $dh, $wsdir )
      || end "Failed to open workspace directory: $!";
    return grep !/^(\.\.?|README)/, readdir($dh);
}

sub image {
    my $image = `yq e '.image' "$wsdir/.config.yml"`;
    chomp $image;
    return $image;
}

sub image_exists {
    my $name = shift;
    `docker image inspect $name >/dev/null 2>&1`;
    return $? == 0;
}

sub x_image {
    my $name = shift;
    my $conf = "$wsdir/.config.yml";
    not $name and say "$image" and return;
    not image_exists($name) and say "Image '$name' not found. Pull." and return;
    not -e $conf and `yq e -n '.image="$name"' >| "$conf"` and return;
    `yq e -i '.image="$name"' "$conf"` and return;
}

sub x_pull {
    my $arg = shift;
    $arg and exec qq{docker pull $arg};
    exec qq{docker pull $image};
}


sub x_config {
    my $name = shift || x_pick();
    say "$wsdir/$name/.config/ws/config.yml";
}

sub x_edit {
    my $name = shift || x_pick();
    my $conf = "$wsdir/$name/.config/ws/config.yml";
    exec $editor, $conf;
}

sub expand {
    my $r = shift;
    return unless @$r;
    map { !/:/; $_ = "$_:$_" } @$r;
}

sub x_open {
    my @names = get_ws_list();
    not @names and return x_create(@_);

    my $name = shift || x_pick();

    my $dir  = "$wsdir/$name";
    not -d $dir and return x_create($name);
    chdir $dir;

    my $confpath=`ws config $name`;
    chomp $confpath;
    not $confpath and end "No config file found.";

    my $username = `yq e .user.name "$confpath"`;
    chomp $username;
    not $username and end "No user name found.";

    my @cmd = (qw(docker run -it --rm --privileged --name), $name, '-h', $name );

    my @ports = qx(yq e '.ports[]' `ws config $name`);
    chomp @ports;
    if ($ports[0] eq 'all') {
        @cmd = ( @cmd, '--network', 'host' );
    } else {
        expand \@ports;
        map { @cmd = ( @cmd, '-p', $_ ) } @ports;
    }

    my @mounts = qx(yq e '.mounts[]' `ws config $name`);
    chomp @mounts;
    unshift @mounts, "/var/run/docker.sock";
    expand \@mounts;
    unshift @mounts, "$dir:/home/$username";
    map { @cmd = ( @cmd, '-v', $_ ) } @mounts;

    #say "Executing: " . join( " ", ( @cmd, $image ) );
    exec( @cmd, $image );
}

sub x_list {
    map { say $_} get_ws_list;
}
*x_ls = *x_list;

sub x_remove {
    my $name = shift;
    $name or $name = x_pick();
    my $path = "$wsdir/$name";
    ! -d $path and say "Path not found: $path" and return;
    print "Sure you want to remove '$path'? (n) ";
    <STDIN> =~ /^y/i or return;
    -d $path and `rm -rf $path`;
    say "Removed $wsdir/$name directory.";
}
*x_rm = *x_remove;

sub x_pick {
    my $n     = 1;
    my @names = get_ws_list();
    not @names and end "No workspaces found.";
    my @list = get_ws_list();
    scalar(@list) == 1 and return $list[0];
    map { say "$n. $_"; $n++ } @list;
    my $pick;
    until ( 0 < $pick && $pick < $n ) {
        print "#? ";
        $pick = <STDIN>;
    }
    my $name = @names[ $pick - 1 ];
    return $name;
}

sub x_usage {
    my @path = split( /\//, $0 );
    my $exe  = pop @path;
    say "usage: $exe [COMMAND]";
}

sub x_create {
    my $name, $dir, $username, $userid, $groupname, $groupid,
      $ports, $mounts, $getlatest, $resp, $confd, $conf;

    $name = shift;
    $dir  = "$wsdir/$name";

    until ($name) {
        print "Workspace Name: ";
        $name = <STDIN>;
        chomp $name;
        not $name and next;
        $dir = "$wsdir/$name";
        if ( -d $dir ) {
            say "Workspace ($name) already exists.";
            $name = "";
            next;
        }
    }

    $username = `id -un`;
    chomp $username;
    print "User Name ($username): ";
    $resp = <STDIN>;
    chomp $resp;
    $resp and $username = $resp;
    $userid = `id -u`;
    chomp $userid;
    say "User ID will be $userid.";

    $shell = $ENV{'SHELL'};
    print "User Shell ($shell): ";
    $resp = <STDIN>;
    chomp $resp;
    $resp and $shell = $resp;

    $groupname = `id -gn`;
    chomp $groupname;
    print "Group Name ($groupname): ";
    $resp = <STDIN>;
    chomp $resp;
    $resp and $groupname = $resp;
    $groupid = `id -g`;
    chomp $groupid;
    say "Group ID will be $groupid.";

    $ports = "";
    printf "Ports: ";
    $resp = <STDIN>;
    chomp $resp;
    $ports = $resp;

    $mounts = '';
    printf "Extra Mounts: ";
    $resp = <STDIN>;
    chomp $resp;
    $mounts = $resp;

    $confd = "$dir/.config/ws/";
    $conf  = "$confd/config.yml";
    -d $dir and end 'Workspace directory already exists: ' . $dir;
    make_path($dir)
      || end 'Failed to create workspace directory: ' . $dir;
    make_path($confd)
      || end 'Failed to create config directory: ' . $confd;
    open( my $fh, ">", $conf )
      || end 'Failed to open config file for writing: ' . $conf;

    say $fh '# This file is used by the ws workspace container manager.';
    say $fh "# It's fine to make changes directly and is shared by host.";
    say $fh "\nname: $name";

    say $fh "\nuser:\n  name: $username\n  id: $userid\n  shell:  $shell";
    say $fh "\ngroup:\n  name: $groupname\n  id: $groupid";
    say $fh "";

    if ($ports) {
        $ports =~ s/ +/,/g;
        say $fh "ports: [$ports]";
    }
    if ($mounts) {
        $mounts = s/ +/,/g;
        say $fh "ports: [$ports]";
    }
    close $fh;

    x_open($name);

}

sub x_dir {
    my $name = shift || x_pick();
    say "$wsdir/$name";
}
*x_d = *x_dir;

# ------------------------ bash tab completion -----------------------
#                  `complete -C ws ws` ->  ~/.bashrc
#                   (any command starting with x_)

if ( $ENV{'COMP_LINE'} ) {
    @completions = grep s/^x_//, keys %{"main::"};
    @completions = ( @completions, get_ws_list );
    if ( not $ARGV[1] ) {
        map { say $_} @completions;
        exit;
    }
    map { /^$ARGV[1]/ && say $_} @completions;
    exit;
}

# ------------------------------- main -------------------------------

if ( not "$ARGV[0]" ) {
    ws_get_list and x_open and exit;
    wx_usage and exit;
}

my $first = shift @ARGV;

$cname = "x_$first";
if (my $func = main->can($cname)) {
    &$func(@ARGV);
    exit;
}

x_open($first);
