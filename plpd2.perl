#! /usr/bin/perl

$debug = 0;

$cmddir = "/usr/etc/finger.cmd";
$dom = "hut.fi";
$AF_INET = 2;
$PF_INET = 2;
$SOCK_STREAM = 1;
$LOCK_SH = 1;
$LOCK_EX = 2;
$LOCK_NB = 4;
$LOCK_UN = 8;

$SIG{'TERM'} = 'handler';

$topname = '.top';
$disablename = '.disable';
$stopname = '.stopped';
#$spooldir = "/u1/users/alo/src/mylpr/spool";
$spooldir = "/v/lpd/spool";
$progdir = "/v/lpd/progs";
$pcapname = "/v/lpd/printcap";
$logfile = "/v/lpd/log/printlog";
$dbfortunename = "/v/lpd/dbfortune";

$pages_peeksize = 4096;

$default_mail_addr = "Operaattorit / ATK-keskus";

chop($hostname = `hostname`);
#($hostname eq 'backup.hut.fi') && ($hostname = 'lpd.hut.fi');
    
chdir($spooldir) || die("Cannot chdir to $spooldir");
&setdebug;

$debug && open(d,">Debug");
select d;
$| = 1;
select(STDOUT);

$o = "stdout";
$| = 1;
#printf "Foobaari\n";

#$pidstr = sprintf("%05d",$$);
#$timestr = sprintf("%010d",(time-700000000)/240);
#$seqstr = sprintf("%03d",$seqno);
$count = 0;

#printf d "%d %s.%d\n",$seqno,$timestr,$pidstr;

@rankarr = ("th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th");

%makepat = ('.','\.',  '*','.*');

if ($hersockaddr = getpeername(STDIN)) {
    $sockaddr = 'S n a4';
    ($family, $port, $heraddr) = unpack($sockaddr, $hersockaddr);

    # if ($port >= 1024) { printf "Illegal port %d\n",$port; exit(1); }
    ($hername) = gethostbyaddr($heraddr, $AF_INET);
    $addr = join('.',unpack("CCCC",$heraddr));
#    $addr = $addr.'.'.$a2.'.'.$a3.'.'.$a4;
    
    select(STDOUT); $| = 1;
    
    $hostfrom = $hername;
    if ($addr || $hername) {
	$hostid = sprintf("%s (%s)",
			  $hername ? $hername : "???",
			  $addr ? $addr : "???");
#	printf $o "Hello %s\n",$hostid;
#	printf $o "Hello %s (%s)\n",$hername ? $hername : "???",
#	$addr ? $addr : "???";
    }
} else {
#    printf $o "No socket\n";
#    exit(0);
}
    
for($readdone = 0; !$readdone ;) {
    $line = <>;
    chop($line);
    if ($line =~ /^(.)(.*)$/) {
	($code,$rest) = ($1,$2);
    }
    
    printf d "Code=%d <%s>\n",ord($code),$rest;
    @args = split(' ',$rest);
    if ($code eq "\017") {
	$queue = $args[0];
	if (&readprintcap($queue)) {
	    if ($pcap{'rm'} && $pcap{'rp'} eq $queue) {
		printf "%s%s","\000\001",$pcap{'rm'};
		exit(0);
	    } else {
		print "\000\000";
	    }
	} else {
	    print "\000\000";
	}
    } else {
	$readdone = 1;
    }
}

if ($code eq "\002") {
    $queue = $args[0];
    if ($queue =~ /[^a-zA-Z0-9\-_]/) { exit(1); }
    &chdir($queue);
    $seqno = &seqno;
    $seqstr = sprintf("%03d",$seqno);
    &rcvjob($queue);
#    &check_access($seqstr);
    &printjobs($queue);
} elsif ($code eq "\003" || $code eq "\004") {
#    printf $o "Hello %s\n",$hostid;
    $queue = $args[0];
    if ($queue =~ /[^a-zA-Z0-9\-_]/ && $queue ne '.') { exit(1); }
    &chdir($queue,1);
    &printqueue($queue,$code eq "\004");
} elsif ($code eq "\001") {
    $queue = $args[0];
    if ($queue =~ /[^a-zA-Z0-9\-_]/) { exit(1); }
    &chdir($queue);
    &printjobs($queue);
} elsif ($code eq "\005") {
    $queue = $args[0];
    if ($queue =~ /[^a-zA-Z0-9\-_]/) { exit(1); }
    &chdir($queue);
    &rmjobs(@args);
    &printjobs($queue);
} elsif ($code eq "\007") {
    $queue = shift(@args);
    if ($queue =~ /[^a-zA-Z0-9\-_]/) { exit(1); }
    &chdir($queue);
    &lpc($queue,@args);
}

#sleep(2);
exit 0;

sub chdir {
    local ($queue,$error_msg) = @_;
    local ($qdir,$ok);
    $ok = $queue eq '.' || &readprintcap($queue);
    if ($pcap{'rm'} && !$pcap{'rp'}) {
	$pcap{'rp'} = $queue;
    }
    if (!($qdir = $pcap{'sd'})) {
	$qdir = $queue;
    }
    if (!$ok || !(chdir($qdir))) {
	printf stderr "No such printer $qdir\n";
	if ($error_msg) {
	    printf "%s: unknown printer\n",$queue;
	}
	exit (1);
    }
    &setdebug;
    $debug && open(d,">Debug0.$$");
    select(d);
    $| = 1;
    select(STDOUT);
    $ENV{"DIR"} = $qdir;
    $class = &current_class;
}

sub setdebug {
    local (*ifi);
    if (open(ifi,".debug")) {
	$debug = (<ifi>)+0;
	close(ifi);
    }
}

sub readinfofile {
    local ($cfname) = @_;
    local ($infoname,*infof,%info,$seqno);

    if ($cfname =~ /^cfA([0-9]{3})/) {
	$seqno = $1;
    } elsif ($cfname =~ /^(ffi|)(\d+)$/) {
	$seqno = sprintf("%03d",$2);
    } else {
	$seqno = '-none';
    }
    $infoname = "ffi$seqno";
    if (open(infof,$infoname)) {
	while ($x = <infof>) {
	    chop($x);
	    if ($x =~ /^([^=]+)=(.*)$/) {
		$info{$1} = $2;
	    }
	}
    }
    %info;
}

sub queueinfo {
    local ($cfname,$long,$rank) = @_;
    local (*f,$infoname,*info,$realqueue,@info,*pagefile);
    local ($x,$fname,$realname,$hdr,$seqno,$bytes,$jobs,$njobs,$pageno);
    local ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	   $atime,$mtime,$ctime,$blksize,$blocks);
    local ($time,$printed) = time;
    local (%fld);
    local ($pages);

    $rank = &prank($rank);
    open(f,$cfname);
    if ($cfname =~ /^cfA([0-9]{3})/) { $seqno = $1; }
    $infoname = "ffi$seqno";
    if (open(info,$infoname)) {
	while ($x = <info>) {
	    chop($x);
	    if ($x =~ /^([^=]+)=(.*)$/) {
		$info{$1} = $2;
	    }
	}
    }
    if (!$info{'etime'}) {
	$info{'etime'} = &getmtime($infoname);
    }
    $realqueue = $info{'queue'};
    $bytes = 0;
    ($jobs,$njobs) = ('','');
    while ($x = <f>) {
	chop($x);
	if ($x =~ /^([CHIJLMPTW])(.*)$/) {
	    $fld{$1} = $2;
	} elsif ($x =~ /^([folptndgcvr])(.*)$/) {
	    if (!$hdr) {
		$hdr = 1;
		if ($long) {
		    printf "\n%-40s [job %s.%s]",
		    $fld{"P"}.":".$rank."   ".$realqueue." ".
			&timediff($time-$info{'etime'}),$seqno,$fld{"H"};
		    if ($cfname eq $currentdf) {
			printf " printing banner";
		    }
		    printf "\n";
		}
	    }
	    $realname = "";
	    $fname = $2;
	} elsif ($x =~ /^([N])(.*)$/) {
	    $realname = $2;
	    if ($class{$cfname}) {
		$realname = '('.$class{$cfname}.') '.$realname;
	    }
	    $printed = (($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			 $atime,$mtime,$ctime,$blksize,$blocks)
			= stat($fname)) == 0;
	    $bytes += $size;
	    if ($long) {
		if ($printed) {
		    printf "        %-24s %13s printed",$realname,"";
		} else {
		    printf "        %-24s %13d bytes",$realname,$size;
		    if ($pages = $info{"$fname-pages"}) {
			printf " %4d pages",$pages;
		    }
		    if ($fname eq $currentdf) {
			if (open(pagefile,".page") && ($pageno = <pagefile>)) {
			    printf "  <-- printed %d pages",$pageno;
			} else {
			    printf "  <-- printing";
			}
		    }
		}
		printf "\n";
	    } else {
		if (!$njobs) {
		    $njobs = $jobs ? $jobs.', '.$realname : $realname;
		    if ($jobs && length($njobs) > 21) {
			$jobs = $jobs.' ...';
		    } else {
			$jobs = $njobs; $njobs = "";
		    }
		}
	    }
	}
    }
    if (!$long) {
	printf "%-6s %-10s %3d  %-11s %-21.21s %11d bytes\n",
	$rank,$fld{"P"},$seqno,$realqueue,$jobs,
	$bytes;
    }
    close(f);
}

sub lpc_help {

    printf "Usage:\n";
    printf "lpc [-P printer] disable\n";
    printf "lpc [-P printer] enable\n";
    printf "lpc [-P printer] stop\n";
    printf "lpc [-P printer] start\n";
    printf "lpc [-P printer] restart\n";
    printf "lpc [-P printer] abort\n";
    printf "lpc [-P printer] down\n";
    printf "lpc [-P printer] up\n";
    printf "lpc [-P printer] topq jobs...\n";
    printf "lpc [-P printer] tailq jobs...\n";
}

sub lpc {
    local ($queue,@args) = @_;
    local ($cmd,$x,*f);

    printf "Queue %s: %s\n",$queue,join(',',@args);
    $cmd = shift(@args);
    if ($cmd eq '' || $cmd eq 'help') { &lpc_help; }
    elsif ($cmd eq 'disable') { open(f,">$disablename"); close(f); }
    elsif ($cmd eq 'enable') { unlink($disablename); }
    elsif ($cmd eq 'stop') { open(f,">$stopname"); close(f); }
    elsif ($cmd eq 'start') { unlink($stopname); &printjobs($queue);}
    elsif ($cmd eq 'restart') {
	open(f,">$stopname"); close(f);
	if (open(f,"lock") && ($pid = <f>) && ($pid = $pid+0)) {
	    kill(15,-$pid);
	}
	close(f);
	unlink($stopname); &printjobs($queue);
    }
    elsif ($cmd eq 'abort') {
	open(f,">$stopname"); close(f);
	if (open(f,"lock") && ($pid = <f>) && ($pid = $pid+0)) {
	    kill(15,-$pid);
	}
	close(f);
    }
    elsif ($cmd eq 'down') {
	open(f,">$disablename");
	print f join(' ',@args),"\n";
	open(f,">$stopname"); close(f);
	if (open(f,"lock") && ($pid = <f>) && ($pid = $pid+0)) {
	    kill(15,-$pid);
	}
	close(f);
    }
    elsif ($cmd eq 'up') { unlink($stopname); unlink($disablename);
			   &printjobs($queue);}
    elsif ($cmd eq 'topq') {
	&topq(@args);
    }
    elsif ($cmd eq 'tailq') {
	&tailq(@args);
    }
    elsif ($cmd eq 'class') {
	&set_class(@args);
    }
    else {
	printf "Illegal command %s, try 'lpc help'\n",$cmd;
    }
}

sub set_class {
    local ($class) = @_;
    local (*f);

    open(f,">.class");
    if ($class ne '') {
	printf f "%s\n",$class;
    }
    close(f);
    &printjobs($queue);
}

sub current_class {
    local ($class);
    local (*f);

    open(f,".class");
    if ($class = <f>) {
	chop($class);
    }
    close(f);
    $class;
}

sub tailq {
    local (@args) = @_;
    local (@jobs) = ();
    local ($x,$num);
    local (%topq) = ();
    local (%topqu) = ();
    local ($time) = time;

    @jobs = &getjobs();
    if (@jobs) {
	while ($x = shift(@args)) {
	    if ($x =~ /^[0-9]+$/) {
		$x = sprintf("%03d",$x);
		$topq{$x} = 1;
	    } else {
		$topqu{$x} = 1;
	    }
	}
	while ($x = pop(@jobs)) {
	    $num = 'xxx';
	    if ($x =~ /^cf.([0-9]{3}).*$/) {
		$num = $1;
	    }
	    if ($topq{$num} || $topqu{$owner{$x}}) {
		printf "tailq %s\n",$x;
		utime($time,$time,$x);
	    }
	}
    }
}

sub topq {
    local (@args) = @_;
    local (@jobs) = ();
    local ($mtime,$x,$num);
    local (%topq) = ();
    local (%topqu) = ();

    @jobs = &getjobs();
    if (@jobs) {
	$mtime = $mtime{$jobs[0]};
	while ($x = shift(@args)) {
	    if ($x =~ /^[0-9]+$/) {
		$x = sprintf("%03d",$x);
		$topq{$x} = 1;
	    } else {
		$topqu{$x} = 1;
	    }
	}
	while ($x = pop(@jobs)) {
	    $num = 'xxx';
	    if ($x =~ /^cf.([0-9]{3}).*$/) {
		$num = $1;
	    }
	    if ($topq{$num} || $topqu{$owner{$x}}) {
		printf "topq %s\n",$x;
		utime($mtime,$mtime,$x);
		$mtime--;
	    }
	}
    }
}

sub getjobs {
    local (@jobs) = ();
    local (@sortedjobs) = ();
    local (*dir,*f);
    local ($x,$x2);
    $x = opendir(dir,".");
    while ($x = readdir(dir)) {
	if ($x =~ /^cf/) {
	    push(@jobs,$x);
	    $mtime{$x} = &getmtime($x);
	    undef($class{$x});
	    open(f,$x);
	    while ($x2 = <f>) {
		chop($x2);
		if ($x2 =~ /^P(.*)$/) {
		    $owner{$x} = $1;
		} elsif ($x2 =~ /^C_class:([^:]*)/) {
		    $class{$x} = $1;
		} 
	    }
	    close(f);
	}
    }
    closedir(dir);
    @sortedjobs = sort bymtime @jobs;
    @sortedjobs;
}

sub printqueue {
    local ($queue,$long) = @_;
    local ($x,@jobs,@sortedjobs,%mtime,*dir,*f);
    local ($currentdf,$status,$linkname);

    if (0 && $long) {
	printf "%s:\n",$hostname;
    }
    if ($class) {
	printf "Current class is %s\n",$class;
    }
    if ($queue eq '.') {
	$x = opendir(dir,".");
	while ($x = readdir(dir)) {
	    if ($x =~ /^[a-zA-Z]/ && (-d "$x/.")) {
		push(@jobs,$x);
	    }
	}
	@sortedjobs = sort bygt @jobs;
	while ($x = shift(@sortedjobs)) {
	    if ($x =~ /^[a-zA-Z]/) {
		if (-l "$x") {
		    $linkname = readlink($x);
		    printf "%s --> %s\n",$x,$linkname;
		} elsif (-d "$x") {
		    printf "%s\n",$x;
		}
	    }
	}
    } else {
	$status = "";
	if (-r $disablename) {
	    $status .= "Queueing disabled. ";
	}
	if (-r $stopname) {
	    $status .= "Printing disabled. ";
	}
	$status =~ s/ *$//;
	if ($status) { printf "%s\n",$status; }
	if (open(f,$disablename)) {
	    while ($x = <f>) {
		print $x;
	    }
	    close(f);
	}
	if (open(f,".currentdf")) {
	    $currentdf = <f>;
	    chop($currentdf);
	    close(f);
	    if ($currentdf =~ /^([^ ]+) (.*)$/) {
		$currentdf = $1;
	    }
	}
	$x = opendir(dir,".");
	@jobs = &getjobs;
	if ($#jobs >= 0 && open(f,"status")) {
	    while ($x = <f>) {
		print $x;
	    }
	    close(f);
	}
	@sortedjobs = sort bymtime @jobs;
	if (@sortedjobs == 0 && !$pcap{'rm'}) {
	    printf "no entries\n";
	}
	for($rank = 0; $x = shift(@sortedjobs); $rank++) {
	    if ($rank == 0 && !$long) {
		printf "Rank   Owner      Job  Queue       Files".
		    "                     Total Size\n";
	    }
	    &queueinfo($x,$long,$rank);
	}
	if ($pcap{'rm'}) {
	    &remote_printqueue($pcap{'rm'},$pcap{'rp'},$long);
	}
    }
}

sub remote_printqueue {
    local ($rmhost,$rmqueue,$long) = @_;
    local ($nbytes,$gotnl,$l) = (0,1);

    if ($long) {
	printf "%s:\n",$rmhost;
    }
    &lpconnect($rmhost,"printer");
    select(sock); $| = 1; select(STDOUT);
    printf sock "%s%s\n",$long ? "\004" : "\003",$rmqueue;
#    &wait_ack;
    while ($x = <sock>) {
	print $x;
	if ($l = length($x)) {
	    $nbytes += $l;
	    $gotnl = (substr($x,$l-1,1) eq "\n");
	}
    }
    if (!$gotnl) {
	print "\n";
    }
}

sub prank {
    local ($rank) = @_;
    local ($r);

    if ($rank == 0) {
	$r = "active";
    } elsif (int($rank/10) == 1) {
	$r = $rank."th";
    } else {
	$r = $rank.$rankarr[$rank%10];
    }
    $r;
}

sub bymtime {
    local ($x);
    ($x = $mtime{$a} - $mtime{$b}) == 0 ? $a cmp $b : $x;
}

sub bygt {
    $a gt $b;
}

sub getsize {
    local ($fname) = @_;
    local (@a) = stat($fname);
    $a[7];
}

sub getmtime {
    local ($fname) = @_;
    local (@a) = stat($fname);
    $a[9];
}

sub getmode {
    local ($fname) = @_;
    local (@a) = stat($fname);
    $a[2];
}

sub rcvjob {
    local ($queue) = @_;
    local ($line);
    local ($args,$code,$rest);
    local ($filesname,$infoname,$savecf);
    local (*info);
    local ($datasize,$pages) = (0,0);

    $savecf = (-e '.savecf');
    @files = ();
    if (-r $disablename) {
	&ackit("Printing disabled\n");
	return;
    }
    &ackit("\000");
    $filesname = "fff$seqstr";
    $infoname = "ffi$seqstr";
    open(files,">$filesname");
    open(info,">$infoname");
    printf info "queue=%s\n",$queue;
    printf info "hostfrom=%s\n",$hername;
    printf info "addrfrom=%s\n",$addr;
    $pcap{'rm'} && printf info "rmhost=%s\n",$pcap{'rm'};
    $pcap{'rp'} && printf info "rmqueue=%s\n",$pcap{'rp'};
    while ($line = <stdin>) {
	($debug > 1) && printf d "Line: %s\n",$line;
	chop($line);
	if ($line =~ /^(.)(.*)$/) {
	    ($code,$rest) = ($1,$2);
	    @args = split(' ',$rest);
	} else {
	    $code = "X";
	}
	if ($code eq "\002") {
	    printf d "%s:cf %d bytes to %s\n",$queue,$args[0],$args[1];
	    &rcvfile($args[0],$args[1],$savecf);
	} elsif ($code eq "\003") {
	    printf d "%s:df %d bytes to %s\n",$queue,$args[0],$args[1];
	    &rcvfile($args[0],$args[1],$savecf);
	    $datasize += $args[0];
	} elsif ($code eq "\001") {
	    printf d "Canceling job %03d\n",$seqno;
	    &rmfiles($seqno);
	} else {
	    printf d "Code=%d <%s>\n",ord($code),$rest;
	}
    }
    ($debug > 1) && printf d "tfname=%s cfname=%s\n",$tfname,$cfname;
    if ($tfname && $cfname) {
	local ($pt);
	if ($pt = $pcap{'pt'}) {
	    &sanitize(@files);
	}
	push(@files,$cfname);
	rename($tfname,$cfname);
	printf files "%s\n",$cfname;
	&log_entry(time,sprintf("%s user=%s sender=%s queue=%s bytes=%d pages=%d",
				&timestring(),$P_username,$hostid,
				$queue,$datasize,$pages));
	$savecf && printf files "%s\n",$tfname.'.orig';
    }
    if ($P_username) {
	printf info "Pvalue=%s\n",$P_username;
    }
    printf info "cfname=%s\n",$cfname;
    close(info);
    push(@files,"ffr$seqstr");
    printf files "%s%s\n","ffr",$seqstr;
    @files = ();
    printf files "%s\n",$infoname;
    printf files "%s\n",$filesname;
    if ($add_banner_file) {
	printf files "%s\n",$add_banner_file;
    }
    close(files);
#    printf d "printjob\n";
#    printf d "printjob ok\n";
}

sub sanitize {
    local (@fn) = @_;
    local ($n,$x,$n2,$n);
    local (*f1,*f2);

    foreach $n (@fn) {
	if ($n =~ /^df/) {
	    open(f1,"<$n");
	    $x = <f1>;
	    if ($x =~ /^\004/) {
		open(f2,">$n.tmp");
		$x =~ s/^\004+//;
		print f2 $x;
		while (($n2 = read(f1,$x,16384)) > 0) {
		    print f2 $x;
		}
		close(f2);
		rename("$n.tmp",$n);
	    }
	    close(f1);
	}
    }
}

sub namereplace {
    local ($n) = @_;
    local ($nn,$type,$num,$host);

    if ($nn = $replace{$n}) {
	;
    } elsif ($n =~ /^cf([A-z])([0-9]{3})(.*)$/) {
	($type,$num,$host) = ('tf'.$1,$2,$3);
	$nn = $type.$seqstr.$hostname;
    } elsif ($n =~ /^(df[A-z])([0-9]{3})(.*)$/) {
	($type,$num,$host) = ($1,$2,$3);
	$nn = $type.$seqstr.$hostname;
    } else {
	$nn = sprintf("of%04d",$count);
	$count++;
    }
    printf d "\$replace{$n} = $nn;\n";
    $replace{$n} = $nn;
    $nn;
}

sub rcvfile {
    local ($size,$name,$savecf) = @_;
    local ($x,$n,$n2,$xx);
    local ($newname,$ok,$check_now);
    local (*of);
    
    &ackit("\000");
    $newname = &namereplace($name);
#    printf d "%s --> %s\n",$name,$newname;
    push(@files,$newname);
    open(of,">$newname");
    printf files "%s\n",$newname;
    for($n = 0; $n < $size; $n += $n2) {
	$n2 = 8192;
	if ($n2 > ($size-$n)) { $n2 = $size-$n; }
	$n2 = read(stdin,$xx,$n2);
	if ($n2 <= 0) { &exit(1); }
	print of $xx;
	if ($savecf) {
	    print of2 $xx;
	}
#	$x = $x.$xx;
    }
    close(of);
    if ($newname =~ /^df/) {
	local ($pages0);
	$pages0 = &count_pages($newname);
	$pages += $pages0;
	$info{"$newname-pages"} = $pages0;
	printf info "%s=%d\n","$newname-pages",$pages0;
    }
    if ($newname =~ /^tf(.*)$/ && !$cfname) {
	($tfname,$cfname) = ($newname,"cf".$1);	# XXX
	printf d "Changing $newname\n";
	if ($savecf) {
	    push(@files,$newname.'.orig');
	    link($newname,$newname.'.orig');
	}
	&changecf($newname);
	printf d "Changed $newname\n";
	$check_now = 1;
    }
    $n2 = read(stdin,$xx,1);
    ($debug > 1) && printf d "Got 0x%02x\n",unpack('C',$xx);
    if ($n2 <= 0) { &exit(1); }
    if ($check_now && $P_username) {
	$ok = &check_access($seqstr,$hostfrom,$P_username);
    } else {
	$ok = 1;
    }
    if ($ok) {
	&ackit("\000");
	if ($add_banner_file) {
	    &add_banner_file($add_banner_file);
	}
    } else {
	&ackit("\002");
    }
}

sub add_banner_file {
    local ($banner_file) = @_;
    local (*f,*ff);
    local ($x);

    open(f,">$banner_file");
    open(ff,"$progdir/DoBanner.ps");
    while ($x = <ff>) {
	print f $x;
    }
    close(ff);
    printf f "(%s@%s) (%s) DoBanner\n",
#    "aaa","bbb","ccc";
    $P_username,$cfHost,$mail_addr;
    close(f);
}

sub changecf {
    local ($name) = @_;
    local (*f);
    local (*nf,*aidx);
    local ($x,$Pvalue,$aix,$val,$add_banner);

    %aidx = ();
    $aix = -e '.aix';
    $add_banner = -e '.banner';
    if ($add_banner) {
	open(f,$name);
	while ($x = <f>) {
	    chop($x);
	    ($x =~ /^C(.*)$/) && ($Class = $1);
	}
    }
    open(f,$name);
    open(nf,">n-$name");
    while ($x = <f>) {
	chop($x);
	($x =~ /^P(.*)$/) && ($Pvalue = $1);
	(($x =~ /^Lalo$/) && $Pvalue) && ($x = "L$Pvalue");
	if ($pcap{'Fl'} && ($x =~ /^f(.*)$/)) {
	    $x = 'l'.$1;
	}
	if ($x =~ /^([folptndgcvrU])(.*)$/) {
	    if ($add_banner) {
		printf nf "f%s\n",&namereplace("dfz".$seqstr."foohost");
		printf nf "U%s\n",&namereplace("dfz".$seqstr."foohost");
		printf nf "N%s\n",$Class ? $Class : "NComputing Centre";
		$add_banner = 0;
		$add_banner_file = &namereplace("dfz".$seqstr."foohost");
		push(@files,$add_banner_file);
	    }
	    $x = $1;
	    $x .= &namereplace($2);
	} elsif ($x =~ /^([HPJ]|(-[NZ]))(.*)$/) {
	    $val = $3;
	    if ($aix && ($1 eq 'H')) {
		$x = $1.$hostname;
		$val = $hostname;
	    }
	    $aidx{$1} = $val;
	    if ($1 eq 'H') {
		$cfHost = $val;
	    }
	}
	printf nf "%s\n",$x;
	printf d "%s\n",$x;
    }
    if (-e '.aidx') {
	if (!$aidx{'-Z'}) {
	    printf nf "-N1\n";
	    printf nf "-Z%s@%s\n",$aidx{'P'},$aidx{'H'};
	    printf nf "-t%s@%s\n",$aidx{'P'},$aidx{'H'};
	    printf nf "-T%s\n",$aidx{'J'};
	}
    }
    close(f);
    close(nf);
    rename("n-$name",$name);
    if ($Pvalue) {
	$P_username = $Pvalue;
    }
}

sub ackit {
    local ($code) = @_;

    printf $o "%s",$code;
}

sub unquote {
    local ($f) = @_;
    if ($f =~ /^[ 	]*"([^"]+)"[ 	]*$/) {
                $f = $1;
	    }
    $f;
}

sub timediff {
    local ($diff) = @_;
    local ($d,$h,$m,$s,$str);
    
    $s = $diff%60;
    $diff = ($diff-$s)/60;
    $m = $diff%60;
    $diff = ($diff-$m)/60;
    $h = $diff%60;
    $diff = ($diff-$h)/60;
    $d = $diff;
    if ($d) {
	$str = sprintf("%d days %02d:%02d.%02d",$d,$h,$m,$s);
    } elsif ($h) {
	$str = sprintf("%02d:%02d.%02d",$h,$m,$s);
    } elsif ($s || $m) {
	$str = sprintf("%02d.%02d",$m,$s);
    } else {
	$str = sprintf("%02ds",$s);
    }
    $str;
}

sub log_entry {
    local ($time,$msg) = @_;
    local (*lf);
    local (@ta) = localtime($time);
    local ($logf) = sprintf("%s-%04d-%02d-%02d",$logfile,1900+$ta[5],$ta[4]+1,$ta[3]);

    open(lf,"+<$logf") || open(lf,"+>>$logf");
    flock(lf,$LOCK_EX);
    seek(lf,0,2);
    $msg =~ s/[\s\n\r]*//;
    print lf $msg,"\n";
    close(lf);
}

sub timestring {
    local ($time);
    $time = shift(@_) || time;
    local ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	localtime($time);
    local($s);
    $s = sprintf("%02d.%02d.%02d %02d:%02d:%02d",
		$mday,$mon+1,$year,$hour,$min,$sec);
    $s;
}

sub seqno {
    local (*seqf);
    local ($seqno);

    open(seqf,"+<.seq") || open(seqf,"+>>.seq");
    
    flock(seqf,$LOCK_EX);
    seek(seqf,0,0);
    $seqno = <seqf>;
    $seqno = ($seqno+1)%1000;
    seek(seqf,0,0);
    printf seqf "%03d\n",$seqno;
    close(seqf);
    $seqno;
}

# Print one job from queue

sub printone {
    local ($queue,$cfname) = @_;
    local ($x,$ffname,$realname,$dfname,$type,$num,$ifname,$fortuneflags);
    local (*tfile,*ffile,*curjob,*jobinfo,*filename,*opts);
    
    %filename = ();
    %opts = ();
    if ($cfname =~ /^cf.([0-9]{3}).*$/) {
	$ffname = "fff$1";
	$num = $1;
    }
    printf d "printone cfname=%s\n",$cfname;
    open(curfile,">.current");
    printf curfile "%d\n",$num;
    close(curfile);
    unlink(".page");
    open(jobinfo,">jobinfo");
    open(tfile,$cfname);
    while ($x = <tfile>) {
	chop($x);
	if ($x =~ /^([folptndgcvr])(.*)$/) {
	    ($type,$dfname) = ($1,$2);
	} elsif ($x =~ /^(N)(.*)$/) {
	    $filename{$dfname} = $2;
	} elsif ($x =~ /^([CHIJLMPTW1234])(.*)$/) {
	    printf jobinfo "cf_$1='$2'\n";
	    $opts{$1} = $2;
	}
    }
    if (defined($pcap{'pw'}) && !defined($opts{'W'})) {
	printf jobinfo "cf_W=%d\n",$pcap{'pw'};
    }
    printf jobinfo "cf_queue='%s'\n",$queue;
    printf jobinfo "cf_af='%s'\n",$pcap{'af'};
    printf jobinfo "cf_lf='%s'\n",$pcap{'lf'};
    printf jobinfo "cf_lp='%s'\n",$pcap{'lp'};
    printf jobinfo "cf_jobno='%03d'\n",$num;
    printf jobinfo "cf_debug='%d'\n",$debug+0;
    if (dbmopen(dbfortune,$dbfortunename,0444)) {
	if ($fortuneflags = $dbfortune{$opts{'P'}}) {
	    printf jobinfo "fortuneflags='%s'\n",$fortuneflags;
	}
	dbmclose(dbfortune);
    }
    close(jobinfo);
    open(jobinfo,">jobs");
    seek(tfile,0,0);
    while ($x = <tfile>) {
	chop($x);
	if ($x =~ /^([folptndgcvrU])(.*)$/) {
	    ($type,$dfname) = ($1,$2);
	    printf jobinfo "%s %s %s\n",$type,$dfname,$filename{$dfname};
	}
    }
    close(tfile);
    close(jobinfo);
    if (!($ifname = $pcap{'if'})) {
	$ifname = "$spooldir/if";
    }
    $rmcurrent = ".currentdf";
    printf d "ifname=%s cfname=%s\n",$ifname,$cfname;
    system("$ifname $cfname");
    $rmcurrent = "";
    open(ffile,$ffname);
    while ($x = <ffile>) {
	chop($x);
	unlink($x);
	printf d "Unlink %s\n",$x;
#	sleep(1);
    }
    close(ffile);
    unlink(".current");
    unlink(".currentdf");
}

sub sendone {
    local ($queue,$cfname) = @_;
    local ($x,$ffname,$realname,$dfname,$type,$num,$ifname);
    local (*tfile,*ffile,*curjob,*jobinfo,*filename,*opts);
    local ($rmhost,$rmqueue);
    local ($reverse,$infoname,%info);
    
    $reverse = (-e '.reverse');
    printf d "Sendone1 %s\n",$cfname;
    %info = &readinfofile($cfname);
    $rmhost = $pcap{'rm'};
    if (!($rmqueue = $pcap{'rp'})) { $rmqueue = $queue; }
    if ($info{'rmqueue'}) {
	$rmqueue = $info{'rmqueue'};
	printf d "rmqueue=%s\n",$rmqueue;
    } else {
	printf d "Still rmqueue=%s\n",$rmqueue;
    }
    &lpconnect($rmhost,"printer");
    select(sock); $| = 1; select(STDOUT);
    printf d "lpconnect %s to queue '%s' \n",$cfname,$rmqueue;
    printf sock "\002%s\n",$rmqueue;
    printf d "First print\n";
    &wait_ack;
    printf d "wait_ack 1 %s\n",$cfname;
    !$reverse && &sendfile(2,$cfname);
    printf d "wait_ack 2 %s\n",$cfname;

    if ($cfname =~ /^cf.([0-9]{3}).*$/) {
	$ffname = "fff$1";
	$num = $1;
    }
    open(ffile,$ffname);
    while ($x = <ffile>) {
	chop($x);
	if ($x =~ /^df/) {
	    &sendfile(3,$x);
	}
    }
    $reverse && &sendfile(2,$cfname);
    seek(ffile,0,0);
    while ($x = <ffile>) {
	chop($x);
	unlink($x);
	printf d "Unlink %s\n",$x;
    }
    close(ffile);
    &waitextra(-e '.waitextra');
    unlink(".current");
}

sub waitextra {
    local ($send0) = @_;
    local ($b,$n);

    if ($send0) {
	printf d "Sending \\000\n";
	print sock "\000";
    }
    shutdown(sock,1);
    if (!(-e '.readextra')) {
	printf d "Waiting extra data\n";
	for($n = 1; $n > 0;) {
	    $n = read(sock,$b,1024);
	    printf d "Got %d bytes '%s'\n",$n,$b;
	}
    }
    printf d "Shutdown(0)\n";
    shutdown(sock,0);
    printf d "Shutdown(0) done\n";
}

sub sendfile {
    local ($type,$name) = @_;
    local (*df,$size,$buf,$n,$ntot,$nname);

    $size = &getsize($name);
    $nname = $name;
#    if ($nname =~ /^cf(.*)$/) {
#	$nname = "cf".$1;
#    }
    if (0 && $nname =~ /\d$/) {
	$nname = $nname . $hostname;
    }
    printf d "Sending file %s %d as %s\n",$name,$size,$nname;
    printf sock "%c%d %s\n",$type,$size,$nname;
    &wait_ack;
    printf d "Sending data %d bytes\n",$size;
    open(df,$name);
    $ntot = 0;
    while (($n = read(df,$buf,8192)) > 0) {
	$ntot += $n;
	print sock $buf;
    }
    if ($ntot < $size) {
	printf d "Too less data from %s\n",$name;
    }
    print sock "\0";
    &wait_ack;
}

sub wait_ack {
    local ($b,$n);

    printf d "Waiting ack\n";
    $n = read(sock,$b,1);
    if ($n != 1) {
	printf d "No ack\n";
	return;
    }
    if ($b ne "\0") {
	printf d "Invalid ack 0x%02x\n",ord($b);
	while ($x = <sock>) {
	    print d $x;
	}
	return;
    }
    printf d "Got ack\n";
}

sub check_access {
    local ($seqno,$hostfrom,$P) = @_;
    local (%info,$ok,@x,$hostpat,$upat);
    local (*info,*accfile,*rfile);
    
    if (!(-e '.access')) {
	return 1;
    }
    if (!$hostfrom || !$P) {
	%info = &readinfofile($seqno);
	$hostfrom = $info{'hostfrom'};
	$P = $info{'Pvalue'};
    }
    open(rfile,">ffr$seqstr");
    if ($hostfrom &&
	$P) {
	printf rfile "hostfrom=%s\n",$hostfrom;
	printf rfile "P=%s\n",$P;
	open(accfile,".access");
	for($ok = 0; !$ok && ($x = <accfile>);) {
	    chop($x);
	    @x = split(/:\s+/,$x);
	    $hostpat = &makepat($x[$[]);
	    $upat = &makepat($x[$[+1]);
	    printf rfile "%s\n",$x;
	    if (($hostfrom eq $x[$[] ||
		 $hostfrom =~ /$hostpat/) &&
		($x[$[+1] eq '' || $x[$[+1] eq $P ||
		 $P =~ /$upat/)) {
		$ok = 1;
		printf rfile "OK %s\n",$x;
		if (!($mail_addr = $x[$[+2])) {
		    $mail_addr = $default_mail_addr;
		}
	    }
	}
	close(accfile);
    } else {
	printf rfile "hostfrom=%s\n",$hostfrom;
	printf rfile "P=%s\n",$P;
	$ok = 0;
    }
    if (!$ok) {
	printf rfile "Remove %s\n",$seqno;
	&rmfiles($seqno);
    }
    printf rfile "ok=%d\n",$ok;
    close(rfile);
    $ok;
}

sub makepat {
    local ($s) = @_;

    $s =~ s/(\.|\*)/$makepat{$1}/eg;
    '^'.$s.'$';
}

sub rmfiles {
    local (@args) = @_;
    local ($x,$x2,$pat,$num,$remove);
    local (*lockf,*current,*f);
    local ($alldone,$locked,$todo,%rm,%rmed,$current,$cfname);

    for($i = $[; $i <= $#args; $i++) {
	$pat .= sprintf("%03d|",$args[$i]);
    }
    chop($pat);
    opendir(dir,".");
    while ($x = readdir(dir)) {
	if ($x =~ /^(cf.|tf.|df.|ff.)([0-9]{3}).*$/) {
	    $num = $2;
	    $remove = ($num =~ /$pat/);
	    if ($remove) {
		unlink($x);
		printf d "Unlink %s\n",$x;
	    }
	}
    }
}
sub rmjobs {
    local (@args) = @_;
    local ($queue);
    local ($rargs);
    local ($x,$x2,@jobs,@sortedjobs,%mtime);
    local (*lockf,*current,*f);
    local ($alldone,$locked,$todo,%rm,%rmed,$current,$cfname);

    $queue = shift(@args);
    $agent = shift(@args);
#    printf "agent=%s\n",$agent;
    $rargs = join(' ',@args);
    while (($x = shift(@args)) ne '') {
	if ($x =~ /^[0-9]+$/) {
	    $x = $x+0;
	}
	$rm{$x} = 1;
	$rmed{$x} = 1;
#	printf "Remove %03d (%s)\n",$x,$x;
    }
    if (open(current,".current")) {
	if ($current = <current>) {
	    $current = $current+0;
	}
	close(current);
    }
    opendir(dir,".");
    while ($x = readdir(dir)) {
	if ($x =~ /^cf.([0-9]{3}).*$/) {
	    $cfname = $x;
	    $ffname = "fff$1";
	    $num = $1+0;
#	    printf "num=%03d (%s)\n",$num,$1;
	    open(f,$cfname);
	    while ($x2 = <f>) {
		chop($x2);
		if ($x2 =~ /^P(.*)$/) {
		    $owner = $1;
		}
	    }
	    close(f);
	    if ((($rm{$num} && ($rmed{$num} = 0,1)) ||
		 ($rm{$owner} && ($rmed{$owner} = 0,1)))) {
		if ($agent eq $owner || $agent eq 'root') {
		    printf "Removing %03d\n",$num;
		    if ($current == $num) {
			if (open(f,"lock")) {
			    if (($pid = <f>) && ($pid = $pid+0)) {
				print "kill(15,-$pid)\n";
				kill(15,-$pid);
			    }
			    close(f);
			}
		    }
		    open(ffile,$ffname);
		    while ($xx = <ffile>) {
			chop($xx);
			unlink($xx);
		    }
		} else {
		    printf "Cannot remove %d\n",$num;
		}
	    }
	}
    }
#    return;
    if ($pcap{'rm'}) {
	&remote_rmjobs($pcap{'rm'},$pcap{'rp'},$rargs);
    }
}

sub remote_rmjobs {
    local ($rmhost,$rmqueue,$args) = @_;
    
    &lpconnect($rmhost,"printer");
    select(sock); $| = 1; select(STDOUT);
    printf sock "%s%s %s %s\n","\005",$rmqueue,$agent,$args;
#    &wait_ack;
    while ($x = <sock>) {
	print $x;
    }
}

sub printjobs {
    local ($queue) = @_;
    local ($x,@jobs,%mtime,$jobqueue);
    local (*lockf,*lockf2,*f);
    local ($alldone,$locked,$todo,$rm);

    close(d);
    if (fork) { return; }
    open(STDIN,"</dev/null");
    open(STDOUT,">/dev/null");
    open(STDERR,">/dev/null");
    setpgrp(0,$$);
    $debug && open(d,">Debug.$$");
    for($alldone = $locked = 0; !$alldone && !(-r $stopname);) {
	if ($todo && !$locked) {
	    open(lockf,"+<lock") || open(lockf,"+>>lock");
	    if (!flock(lockf,$LOCK_EX|$LOCK_NB)) {
		printf d "Cannot lock\n";
		exit(0);
	    } else {
		printf d "Locked lock\n";
		$rmlock = "lock";
	    }
	    $locked = 1;
	}
	$x = opendir(dir,".");
	@jobs = &getjobs;
#	&print_arr(".foo",@jobs);
	@jobs = sort bymtime @jobs;
#	&print_arr(".foo2",@jobs);
	$todo = ($#jobs >= 0);
	if ($pcap{'DM'}) {
	    $todo = 0;
	} elsif ($todo && $class) {
	    $todo = 0;
	    for($x = 0; !$todo && $x <= $#jobs; $x++) {
		if ($class eq $class{$jobs[$x]}) { $todo = 1; }
	    }
	}
	$alldone = !$todo && !$locked;
	if ($locked) {
	    if ($todo) {
		for(; ($x = shift(@jobs)) && !(-r $stopname);) {
		    open(lockf2,">lock"); close(lockf2);
		    seek(lockf,0,0);
		    printf lockf "%d\n%s\n",$$,$x;
		    seek(lockf,0,0);
		    $jobqueue = &jobqueue($x,$queue);
		    printf d "jobqueue=%s\n",$jobqueue;
		    if ($pcap{'rm'}) {
			&sendone($jobqueue,$x);
		    } elsif ($pcap{'DM'}) {
			;
		    } else {
			if ($class eq $class{$x}) {
			    printf d "&printone($jobqueue,$x);\n";
			    &printone($jobqueue,$x);
			}
		    }
		}
		$todo = 0;
	    }
	    open(lockf2,">lock"); close(lockf2);
	    $rmlock = "";
	    unlink("lock");
	    close(lockf);
	    $locked = 0;
	}
    }
}

sub jobqueue {
    local ($cfname,$default) = @_;
    local ($q,*f);

    if (($cfname =~ /^cf.([0-9]{3})/) &&
	open(f,"ffi$1") &&
	($q = <f>) && (chop($q),1) &&
	($q =~ /^queue=(.*)$/)) {
	$q = $1;
    } else {
	$q = $default;
    }
    $q;
}

sub readprintcap {
    local ($queue) = @_;
    local ($done,$x,$line,$xx,$ok);
    local (@a,@n,*pcapf);

    $done = 0;
    if ($pcap{'queue'} eq $queue) {
	return 1;
    }
    %pcap = ();
    $ok = open(pcapf,$pcapname);
#    printf d "Opened %s %d\n",$pcapname,$ok;
    if (!$ok) { return 0; }
    $ok = 0;
    for(;!$done || $line;) {
	if ($line) {
	    if ($line =~ /^(.*)\\$/) {
		if ($x = <pcapf>) {
		    chop($x); $line = $line.$x;
		} else {
		    $line = $1;
		    $done = 1;
		}
	    } else {
		if ($line =~ /^([^:]*)/) {
		    $xx = "|$1|";
		} else {
		    $xx = "";
		}
		if ($xx =~ m/\|$queue\|/) {
#		    printf d "Found match %s\n",$queue;
		    $ok = 1;
		    @a = split(':',$line);
		    shift(@a);
		    while ($x = shift(@a)) {
			if ($x =~ m@^([a-zA-Z]{2})(([=\#])(.*)|)$@) {
#			    printf "  1=<%s> 3=<%s> 4=<%s>\n",$1,$3,$4;
			    printf d "%s=%s\n",$1,$4;
			    $pcap{$1} = $4;
			}
		    }
		} else {
		    printf d "No match %s\n",$xx;
		}
		$line = "";
	    }
	} else {
	    if ($x = <pcapf>) {
		chop($x); $line = $x;
	    } else {
		$done = 1;
	    }
	}
    }
    $pcap{'queue'} = $queue;
    $ok;
}

sub die {
    local ($str);
    printf d "Died %s\n",$str;
    exit(1);
}

sub lpconnect {
    local ($host,$port) = @_;
    local ($name,$aliases,$proto,$type,$len,$thataddr,$sockaddr);
    local ($oselect,$myport,$myport0,$i);
    local $ii0;

#    require 'sys/socket.ph';
    
    printf d "lpconnect 1\n";

#    $sockaddr = 'S n a4 x8';
    $sockaddr = 'n n a4 x8';
    ($name, $aliases, $proto) = getprotobyname('tcp');
    ($name, $aliases, $port) = getservbyname($port, 'tcp')
	unless $port =~ /^\d+$/;
    (($name, $aliases, $type, $len, $thataddr) = gethostbyname($host)) ||
	&die("gethostbyname: $!");
    
    $that = pack($sockaddr, $AF_INET, $port, $thataddr);

    socket(sock, $PF_INET, $SOCK_STREAM, $proto) || &die("socket: $!");
    $myport0 = $$%512;
    printf d "lpconnect 2 myport=%d\n",$myport0;
    for($i = 0; $i < 512; $i++) {
	$myport = ($myport0+$i)%512+512;
	$this = pack($sockaddr, $AF_INET, $myport, "\000\000\000\000");
	$ii0 = $i;
	last if bind(sock, $this);
    }
    printf d "lpconnect 3 i=%d myport=%d\n",$ii0,$myport;
    &die("Cannot bind privileged socket") if ($i == 512);
    if (!connect(sock, $that)) {
	printf d "lpconnect failed %s <%s>\n",$!,$that;
	die "connect: $!";
    }
    printf d "lpconnect 4\n";
}

sub handler {
    local($sig) = @_;
    if ($rmlock) { unlink($rmlock); }
    if ($rmcurrent) { unlink($rmcurrent); }
    exit(0);
}

sub exit {
    local ($code) = @_;

    while ($#files >= 0) {
	unlink(shift(@files));
    }
    exit($code);
}

sub print_arr {
    local ($fname,@a) = @_;
    local ($x);
    local (*foo);

    open(foo,">$fname");
    printf foo "%d lines\n",$#a+1;
    for($x = 0; $x <= $#a; $x++) {
	printf foo "%s\n",$a[$x];
    }
    close(foo);
}

sub read_Pages {
  local ($buffer) = @_;
  local ($line);

  for (split(/\n/, $buffer)) {
      if (/^%%\s*Pages:\s*(\d+)/) {
	  return $1;
      }
  }

  undef;
}

sub count_pages {
    local ($psfile) = @_;
    local ($buffer);
    local ($guessed) = (0);
    
    local ($Pages);
    local (*PSFILE);
    if (open(PSFILE, $psfile)) {
	unless (defined $Pages) {
	    sysread(PSFILE, $buffer, $pages_peeksize);
	    $Pages = &read_Pages($buffer);
	}
	unless (defined $Pages) {
	    seek(PSFILE, -$pages_peeksize, 2);
	    sysread(PSFILE, $buffer, $pages_peeksize);
	    $Pages = &read_Pages($buffer);
	}
	if (defined $Pages) {
	    # print "$psfile $Pages\n";
	    $guessed++;
	} else {
	    # warn "$0: $psfile: cannot guess Pages\n";
	    ;
	}
    } else {
	# warn "$0: failed to open '$psfile' for reading: $!\n";
	;
    }
    $Pages;
}
