#include <strings.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>

#include <sys/types.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/file.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netdb.h>
#include <ctype.h>
#include <stdio.h>
#include <errno.h>
#include <pwd.h>

extern char	*getlogin();
extern char	*my_getlogin();

u_long	inet_addr();
int	timeout = 2;

int	conf_pending_lines = 20;
int	conf_flush_treshold = 10;

char	*user_passwd = 0;
char	*unix_passwd = 0;
char	*unix_uid = 0;
char	*ena_passwd = 0;

char	*force_username = 0;

int	dflag;
int	only_to;

char	*queue;

char	myhostname[128];
char	*tmp_prefix = "/tmp/";
char	*lpr_config = "/etc/lpr_config\000xxxxxxxxxxxxxxxxx";
char	lpr_default_host0[128] = "Lpd:";
char	*lpr_default_host = &lpr_default_host0[4];
char	lpr_reverse_command[128] = "Reverse:";
#define REVERSE (lpr_reverse_command[8])
char	lpr_redirect_buffer[] = "Redirect:\000";
#define REDIRECT (lpr_redirect_buffer[9])
char	*class;
int	format = 'f';
int	copies = 1;
int	indent = 0;
int	width = 80;
int	rflag;
int	mflag;
int	hflag;
int	sflag;
int	lflag;

char	*lpd_host;
char	*lpd_port;

char	*str_copies;
char	*str_indent;
char	*str_width;

char	*username;
char	*font[4];
char	*title;
char	*jobname;


int
mysocket(int a1, int a2, int a3)

{
  struct sockaddr_in sin;
  int s;
  int	ntries = IPPORT_RESERVED/2;
  int	nmod = IPPORT_RESERVED/2;
  int	nadd = IPPORT_RESERVED/2;
  int	portno;
  int	i;
  
  sin.sin_family = AF_INET;
  sin.sin_addr.s_addr = INADDR_ANY;
  s = socket(AF_INET, SOCK_STREAM, 0);
  if (s < 0)
    return (-1);
  portno = getpid();
  for (i = 0; i < ntries; i++) {
    sin.sin_port = htons((u_short)(((i+portno)%nmod)+nadd));
    if (bind(s, (struct sockaddr *)&sin, sizeof (sin)) >= 0)
      return (s);
    if (errno == EACCES) {
      close(s);
      s = socket(AF_INET, SOCK_STREAM, 0);
      if (s < 0)
	return (-1);
      return (s);
    }
    if (errno != EADDRINUSE) {
      (void) close(s);
      return (-1);
    }
  }
  return -1;
}

int
my_connect(int s, struct sockaddr *addr, int addr_len, int ntries, int wait_sec)

{
  int	i;
  int	r;

  for(i = 0; i < ntries; i++) {
    if (i != 0)
      sleep(wait_sec);
    r = connect(s,(void*)addr,addr_len);
    if (r == 0)
      return r;
    if (r == -1 && errno != ECONNREFUSED) {
      return r;
    }
  }
  return -1;
}

int
myread(fd,buf,n)

int	fd;
char	*buf;
int	n;

{
  int	nr;
  int	n2;

  for(nr = 0; nr < n && n2; nr += n2) {
    n2 = read(fd,buf+nr,n-nr);
    if (n2 <= 0) n2 = 0;
  }
  return nr;
}

void
reset_uid()

{
  int	ruid;
  ruid = getuid();
  if (ruid) {
    if (lpd_port) lpd_port = 0;
  }
#if BSD
  setreuid(ruid,ruid);
#else
  setuid(ruid);
#endif
}

int
ackok(int s)

{
  int	n;
  char	c;

  n = read(s,&c,1);
  return (n == 1 && c == 0);
}

int
tmp_file()

{
  int	fd;
  char	buf[128];
  static int	counter = 0;

  sprintf(buf,"%s%s%05d.%d",tmp_prefix,".lpr",getpid(),counter);
  counter++;
  fd = open(buf,O_RDWR|O_CREAT|O_TRUNC,0000);
  if (dflag < 2)
    unlink(buf);
  return fd;
}

int
open_connection(host)

char	*host;

{
  struct hostent	*hp;
  struct servent	*sp,spb;
  struct sockaddr_in	sin;
  int			server;
  int			connected;
  int			i;

  sin.sin_addr.s_addr = inet_addr(host);
  if (sin.sin_addr.s_addr != -1) {
    sin.sin_family = AF_INET;
  } else {
    hp = gethostbyname(host);
    if (hp == NULL) {
      (void) fprintf(stderr,"%s: unknown host\n", host);
      exit(1);
    }
    sin.sin_family = hp->h_addrtype;
    bcopy(hp->h_addr_list[0], (caddr_t)&sin.sin_addr,
	  hp->h_length);
  }
  sp = getservbyname(lpd_port ? lpd_port : "printer", "tcp");
  if (sp == 0) {
    sp = &spb;
    sp->s_port = ntohs(atoi(lpd_port));
  }
  if (sp == NULL) {
    perror("port/tcp");
    exit(1);
  }
  sin.sin_port = sp->s_port;
  for(connected = 0; !connected;) {
    server = mysocket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) {
      perror("lpr: socket");
      exit(1);
    }
    
    if (my_connect(server, (struct sockaddr *)&sin, sizeof (sin),20,10) < 0) {
      if (hp && hp->h_addr_list[1]) {
	hp->h_addr_list++;
	bcopy(hp->h_addr_list[0],
	      (caddr_t)&sin.sin_addr, hp->h_length);
	(void) close(server);
	continue;
      }
      perror("lpr: connect");
      exit(1);
    }
    connected++;
  }
  return server;
}

int
open_connection_cmd(host,queueptr)

char	*host;
char	**queueptr;

{
  int	fd = -1;
  char	b[128];
  char	hostbuf[128];
  int	ok;
  int	n;

  if (REDIRECT) {
    for(ok = 0; !ok;) {
      fd = open_connection(host);
      write(fd,"\017",1);
      write(fd,queue,strlen(queue));
      write(fd,"\n",1);
      n = read(fd,b,1);
      if (n == 1 && b[0] == 0) {
	n = read(fd,b,1);
	if (n == 1) {
	  if (b[0] == 0) {
	    ok = 1;
	    if (dflag)
	      fprintf(stderr,"Host <%s> is OK\n",host);
	  } else {
	    n = myread(fd,b,sizeof(b)-1);
	    b[n] = 0;
	    if (dflag)
	      fprintf(stderr,"Redirected from <%s> to <%s>\n",host,b);
	    host = hostbuf;
	    strcpy(host,b);
	    close(fd);
	    fd = -1;
	  }
	} else {
	  if (dflag)
	    fprintf(stderr,"Server <%s> cannot redirect\n",host);
	  ok = 1;
	  close(fd);
	  fd = -1;
	}
      } else {
	if (dflag)
	  fprintf(stderr,"Server <%s> cannot redirect\n",host);
	ok = 1;
	close(fd);
	fd = -1;
      }
    }
  }
  if (fd == -1) {
    fd = open_connection(host);
  }
  reset_uid();
  return fd;
}

void
set_lpd_host(hostname)

char	*hostname;

{
  if (getuid() == 0) {
    lpd_host = hostname;
  }
}

void
setusername(username)

char	*username;

{
  if (getuid() == 0) {
    force_username = username;
  }
}

int
get_lpdhostname1(dp,queue)

char	*dp;
char	*queue;

{
  FILE	*f = 0;
  int	r = 0;
  char	s[1024];
  char	s2[1024];

  if (!(f = fopen(lpr_config,"r")))
    goto err;
  while (fgets(s,sizeof(s),f)) {
    if (s[0] == '#') continue;
    if (sscanf(s,"%s %s",s2,dp) == 2 &&
	(strcmp(s2,queue) == 0 || strcmp(s2,".") == 0)) {
      r = 1;
      break;
    }
  }
 err:
  if (f) fclose(f);
  return r;
}

int
get_lpdhostname2(dp)

char	*dp;

{
  if (lpr_default_host[0]) {
    strcpy(dp,lpr_default_host);
    return 1;
  } else
    return 0;
}

int
get_lpdhostname3(dp)

char	*dp;

{
  char	*p;
  char	b[1024];
  gethostname(b,1024);
  if ((p = index(b,'.'))) {
    strcpy(dp,"lpd");
    strcat(dp,p);
    return 1;
  }
  dp[0] = 0;
  return 0;
}

int
get_lpdhostname(dp,queue)

char	*dp;
char	*queue;

{
  return (get_lpdhostname1(dp,queue) ||
	  get_lpdhostname2(dp) ||
	  get_lpdhostname3(dp));
}

int
myatoi(s,flag)

char	*s;
char	*flag;

{
  int	x;

  if (sscanf(s,"%d",&x) != 1 &&
      sscanf(s,"0x%x",&x) != 1 &&
      sscanf(s,"0X%x",&x) != 1 &&
      sscanf(s,"0%o",&x) != 1) {
    fprintf(stderr,"Illegal option -%s %s\n",flag,s);
    exit(1);
  }
  return x;
}
  
void
construct_fd(buf,c,fnumber)

char	*buf;
int	c;
int	fnumber;

{
  fnumber += 'A';
  sprintf(buf,"%cf%c%03d%s",c,fnumber,getpid()%1000,myhostname);
}

int
copy_file(fd1,fd2,code,name)

int	fd1;
int	fd2;
int	code;
char	*name;

{
  struct stat	statb;
  int		ok;
  char		ss[128];
  long		oldpos;

  fstat(fd1,&statb);
  {
    long int	size;
    size = statb.st_size;
    if (size != statb.st_size) {
      fprintf(stderr,"File too big %s\n",name);
      return 0;
    }
    sprintf(ss,"%c%ld %s\n",code,size,name);
  }
  write(fd2,ss,strlen(ss));
  ok = ackok(fd2);
  if (!ok) {
    fprintf(stderr,"Printer cannot accept file %s\n",name);
  } else {
    char	b[8192];
    int		n,n0;
    oldpos = lseek(fd1,0,1);
    lseek(fd1,0,0);
    n0 = statb.st_size;
    while(n0 > 0 && (n = read(fd1,b,sizeof(b))) > 0) {
      if (n > n0) n = n0;
      write(fd2,b,n);
      n0 -= n;
    }
    lseek(fd1,oldpos,0);
    if (n0 > 0)
      return 0;
    b[0] = 0;
    write(fd2,b,1);
    ok = ackok(fd2);
    if (!ok) {
      fprintf(stderr,"Printer didn't accept file %s\n",name);
    }
  }
  return ok;
}


int
copy_fd0(fd0)

int	fd0;

{
  int	fd;
  char	b[8192];
  int		n;

  fd = tmp_file();
  while((n = read(fd0,b,sizeof(b))) > 0) {
    write(fd,b,n);
  }
  lseek(fd,0,0);
  return fd;
}

void
send_file(s,real_file,name,dfname)

int	s;
int	real_file;
char	*name;
char	*dfname;

{
  char	ss[128];
  int		fd = -1;
  int		ok;
  struct stat	statb;

  if (!real_file) {
    fd = copy_fd0(0);
  } else {
    fd = open(name,O_RDONLY,0);
  }
  if (fd < 0) {
    fprintf(stderr,"lpr: cannot open %s: %s\n",name,strerror(errno));
    return;
  }
  fstat(fd,&statb);
  ok = copy_file(fd,s,3,dfname);
  close(fd);
  if (!ok) {
    fprintf(stderr,"Spooler didn't accept %s (%s)\n",name,dfname);
  }
}

int
main_lpc(argc,argv,envp)

int argc;
char **argv;
char **envp;

{
  int	c;
  int	lpd_fd = -1;
  char	ss[128];
  int	ok;
  int	cfd;
  FILE	*cfile;
  char	buf[512];
  int	i;
  int	argslen;
  char	**pp,*args,*p;
  
  while ((c = getopt(argc,argv,"=:H:DP:lU:")) != EOF) {
    switch (c) {
    case '=': lpd_port = optarg; break;
    case 'H': set_lpd_host(optarg); break;
    case 'P': queue = optarg; break;
    case 'l': lflag++; break;
    case 'D': dflag++; break;
    case 'U': setusername(optarg); break;
    }
  }
  argv += optind;

  if (!queue) queue = getenv("PRINTER");
  if (!queue) queue = "lp";

  if (!lpd_host) {
    static char	b[1024];
    if (get_lpdhostname(b,queue))
      lpd_host = b;
    else {
      fprintf(stderr,"Cannot find lpd host name\n");
      exit(1);
    }
  }
  if (getuid()) {
    fprintf(stderr,"lpc needs root privileges\n");
    exit(1);
  }
  gethostname(myhostname,sizeof(myhostname));

  username = my_getlogin();

  lpd_fd = open_connection_cmd(lpd_host,&queue);

  for(argslen = strlen(queue)+20, pp = argv; *pp; pp++)
    argslen += strlen(*pp)+1;
  args = malloc(argslen+10);
  if (!args) {
    fprintf(stderr,"Cannot malloc %d bytes\n",argslen);
    exit(1);
  }
  args[0] = 0;
  p = args;
  *p++ = 7;
  strcpy(p,queue);
  p += strlen(p);
  for(argslen = 0, pp = argv; *pp; pp++) {
    int	l = strlen(*pp);
    *p++ = ' ';
    strcpy(p,*pp);
    p += l;
  }
  *p++ = '\n';
  *p = 0;

  write(lpd_fd,args,strlen(args));

  {
    char	b[8192];
    int		n;
    while ((n = read(lpd_fd,b,sizeof(b))) > 0) {
      write(1,b,n);
    }
  }

  exit(0);
}
  
int
main_lpq(argc,argv,envp)

int argc;
char **argv;
char **envp;

{
  int	c;
  int	lpd_fd = -1;
  char	ss[128];
  int	ok;
  int	cfd;
  FILE	*cfile;
  char	buf[512];
  int	i;
  
  while ((c = getopt(argc,argv,"=:H:DP:lU:")) != EOF) {
    switch (c) {
    case '=': lpd_port = optarg; break;
    case 'H': set_lpd_host(optarg); break;
    case 'P': queue = optarg; break;
    case 'l': lflag++; break;
    case 'D': dflag++; break;
    case 'U': setusername(optarg); break;
    }
  }
  argv += optind;

  if (!queue) queue = getenv("PRINTER");
  if (!queue) queue = "lp";

  if (!lpd_host) {
    static char	b[1024];
    if (get_lpdhostname(b,queue))
      lpd_host = b;
    else {
      fprintf(stderr,"Cannot find lpd host name\n");
      exit(1);
    }
  }
  gethostname(myhostname,sizeof(myhostname));

  if (!class) class = myhostname;
  username = my_getlogin();

  lpd_fd = open_connection_cmd(lpd_host,&queue);

  sprintf(ss,"%c%s\n",lflag ? 4 : 3,queue);
  write(lpd_fd,ss,strlen(ss));

  {
    char	b[8192];
    int		n;
    while ((n = read(lpd_fd,b,sizeof(b))) > 0) {
      write(1,b,n);
    }
  }

  exit(0);
}
  
int
main_lpstart(argc,argv,envp)

int argc;
char **argv;
char **envp;

{
  int	c;
  int	lpd_fd = -1;
  char	ss[128];
  int	ok;
  int	cfd;
  FILE	*cfile;
  char	buf[512];
  int	i;
  
  while ((c = getopt(argc,argv,"=:H:DP:U:")) != EOF) {
    switch (c) {
    case '=': lpd_port = optarg; break;
    case 'H': set_lpd_host(optarg); break;
    case 'P': queue = optarg; break;
    case 'D': dflag++; break;
    case 'U': setusername(optarg); break;
    }
  }
  argv += optind;

  if (!queue) queue = getenv("PRINTER");
  if (!queue) queue = "lp";

  if (!lpd_host) {
    static char	b[1024];
    if (get_lpdhostname(b,queue))
      lpd_host = b;
    else {
      fprintf(stderr,"Cannot find lpd host name\n");
      exit(1);
    }
  }
  gethostname(myhostname,sizeof(myhostname));

  if (!class) class = myhostname;
  username = my_getlogin();
  lpd_fd = open_connection_cmd(lpd_host,&queue);

  sprintf(ss,"%c%s\n",1,queue);
  write(lpd_fd,ss,strlen(ss));

  {
    char	b[8192];
    int		n;
    while ((n = read(lpd_fd,b,sizeof(b))) > 0) {
      write(1,b,n);
    }
  }

  exit(0);
}
  
int
main_lprm(argc,argv,envp)

int argc;
char **argv;
char **envp;

{
  int	c;
  int	lpd_fd = -1;
  char	ss[128];
  int	ok;
  int	cfd;
  FILE	*cfile;
  char	buf[512];
  int	i;
  char	*args,**pp,*p;
  int	argslen;
  
  while ((c = getopt(argc,argv,"=:H:DP:lU:")) != EOF) {
    switch (c) {
    case '=': lpd_port = optarg; break;
    case 'H': set_lpd_host(optarg); break;
    case 'P': queue = optarg; break;
    case 'D': dflag++; break;
    case 'U': setusername(optarg); break;
    }
  }
  argv += optind;

  if (!queue) queue = getenv("PRINTER");
  if (!queue) queue = "lp";

  for(argslen = 0, pp = argv; *pp; pp++)
    argslen += strlen(*pp)+1;
  args = malloc(argslen+10);
  if (!args) {
    fprintf(stderr,"Cannot malloc %d bytes\n",argslen);
    exit(1);
  }
  args[0] = 0;
  p = args;
  for(argslen = 0, pp = argv; *pp; pp++) {
    int	l = strlen(*pp);
    strcpy(p,*pp);
    p += l;
    *p++ = ' ';
  }
  if (p > args)
    *--p = 0;

  if (!lpd_host) {
    static char	b[1024];
    if (get_lpdhostname(b,queue))
      lpd_host = b;
    else {
      fprintf(stderr,"Cannot find lpd host name\n");
      exit(1);
    }
  }
  gethostname(myhostname,sizeof(myhostname));

  if (!class) class = myhostname;
  username = my_getlogin();

  lpd_fd = open_connection_cmd(lpd_host,&queue);
  sprintf(ss,"%c%s %s %s\n",5,queue,username,args);
  write(lpd_fd,ss,strlen(ss));
  {
    char	b[8192];
    int		n;
    while ((n = read(lpd_fd,b,sizeof(b))) > 0) {
      write(1,b,n);
    }
  }

  exit(0);
}
  
int
main_lpr(argc,argv,envp)

int argc;
char **argv;
char **envp;

{
  int	c;
  int	lpd_fd = -1;
  char	ss[128];
  int	ok;
  int	cfd;
  FILE	*cfile;
  char	buf[512];
  int	i;
  
  while ((c = getopt(argc,argv,"=:DP:#:C:J:T:i:w:1:2:3:4:lptndgcvfrmhsH:U:"))
	 != EOF) {
    switch (c) {
    case '=': lpd_port = optarg; break;
    case 'P': queue = optarg; break;
    case '#': str_copies = optarg; break;
    case 'C': class = optarg; break;
    case 'J': jobname = optarg; break;
    case 'T': title = optarg; break;
    case 'i': str_indent = optarg; break;
    case 'w': str_width = optarg; break;
    case '1': case '2': case '3': case '4':
      font[c-'1'] = optarg; break;
    case 'l': case 'p': case 't': case 'n': case 'd':
    case 'g': case 'c': case 'v': case 'f':
      format = (c == 'f') ? 'r' : c;
    case 'D':
      dflag++;
      break;
    case 'r': rflag++; break;
    case 'm': mflag++; break;
    case 'h': hflag++; break;
    case 's': sflag++; break;
    case 'H': set_lpd_host(optarg); break;
    case 'U': setusername(optarg); break;
    }
  }
  argv += optind;

  if (!queue) queue = getenv("PRINTER");
  if (!queue) queue = "lp";

  if (str_copies) copies = myatoi(str_copies,"#");
  if (str_indent) indent = myatoi(str_copies,"i");
  if (str_width) width = myatoi(str_width,"w");

  if (!lpd_host) {
    static char	b[1024];
    if (get_lpdhostname(b,queue))
      lpd_host = b;
    else {
      fprintf(stderr,"Cannot find lpd host name\n");
      exit(1);
    }
  }
  gethostname(myhostname,sizeof(myhostname));

  if (!class) class = myhostname;
  username = my_getlogin();

  lpd_fd = open_connection_cmd(lpd_host,&queue);
  sprintf(ss,"\002%s\n",queue);
  write(lpd_fd,ss,strlen(ss));
  ok = ackok(lpd_fd);
  if (!ok) {
    fprintf(stderr,"Printer cannot accept jobs\n");
    return 1;
  }
  cfd = tmp_file();
  cfile = fdopen(cfd,"w+");
  fprintf(cfile,"H%s\n",myhostname);
  fprintf(cfile,"P%s\n",username);
  fprintf(cfile,"J%s\n",jobname ? jobname : (*argv ? *argv : "stdin"));
  fprintf(cfile,"C%s\n",class);
  if (!hflag) fprintf(cfile,"L%s\n",username);
  if (str_indent) fprintf(cfile,"I%d\n",indent);
  if (str_width) fprintf(cfile,"W%d\n",width);
  if (title) fprintf(cfile,"T%s\n",title);
  if (mflag) fprintf(cfile,"M%s\n",username);
  for(i = 0; i < 4; i++) {
    if (font[i]) fprintf(cfile,"%d%s\n",i,font[i]);
  }
  {
    int	fnumber,i;
    char	**pp;
    if (*argv) {
      for(fnumber = 0, pp = argv; *pp; pp++, fnumber++) {
	construct_fd(buf,'d',fnumber);
	for(i = 0; i < copies; i++)
	  fprintf(cfile,"f%s\n",buf);
	fprintf(cfile,"U%s\n",buf);
	fprintf(cfile,"N%s\n",*pp);
      }
    } else {
      construct_fd(buf,'d',0);
      for(i = 0; i < copies; i++)
	fprintf(cfile,"f%s\n",buf);
      fprintf(cfile,"U%s\n",buf);
      fprintf(cfile,"N%s\n","stdin");
    }
    fflush(cfile);
    fseek(cfile,0,0);
    construct_fd(buf,'c',0);
    copy_file(fileno(cfile),lpd_fd,2,buf);
    fclose(cfile);
    if (*argv) {
      for(fnumber = 0, pp = argv; *pp; pp++, fnumber++) {
	construct_fd(buf,'d',fnumber);
	send_file(lpd_fd,1,*pp,buf);
	if (rflag)
	  unlink(*pp);
      }
    } else {
      construct_fd(buf,'d',0);
      send_file(lpd_fd,0,"stdin",buf);
    }
  }
  exit(0);
}
  
int
main_lp(argc,argv,envp)

int argc;
char **argv;
char **envp;

{
  int	c;
  int	lpd_fd = -1;
  char	ss[128];
  int	ok;
  int	cfd;
  FILE	*cfile;
  char	buf[512];
  int	i;
  
  while ((c = getopt(argc,argv,"=:cDd:n:t:msH:U:o:"))
	 != EOF) {
    switch (c) {
    case '=': lpd_port = optarg; break;
    case 'd': queue = optarg; break;
    case 'c': break;
    case 'n': str_copies = optarg; break;
    case 't': title = optarg; break;
    case 'm': mflag++; break;
    case 's': ; break;
    case 'H': set_lpd_host(optarg); break;
    case 'U': setusername(optarg); break;
    case 'o': /* set_lp_options(optarg); */ break;
    }
  }
  argv += optind;

  if (!queue) queue = getenv("PRINTER");
  if (!queue) queue = "lp";

  if (str_copies) copies = myatoi(str_copies,"#");
  if (str_indent) indent = myatoi(str_copies,"i");
  if (str_width) width = myatoi(str_width,"w");

  if (!lpd_host) {
    static char	b[1024];
    if (get_lpdhostname(b,queue))
      lpd_host = b;
    else {
      fprintf(stderr,"Cannot find lpd host name\n");
      exit(1);
    }
  }
  gethostname(myhostname,sizeof(myhostname));

  if (!class) class = myhostname;
  username = my_getlogin();

  lpd_fd = open_connection_cmd(lpd_host,&queue);
  sprintf(ss,"\002%s\n",queue);
  write(lpd_fd,ss,strlen(ss));
  ok = ackok(lpd_fd);
  if (!ok) {
    fprintf(stderr,"Printer cannot accept jobs\n");
    return 1;
  }
  cfd = tmp_file();
  cfile = fdopen(cfd,"w+");
  fprintf(cfile,"H%s\n",myhostname);
  fprintf(cfile,"P%s\n",username);
  fprintf(cfile,"J%s\n",*argv ? *argv : "stdin");
  fprintf(cfile,"C%s\n",class);
  if (!hflag) fprintf(cfile,"L%s\n",username);
  if (str_indent) fprintf(cfile,"I%d\n",indent);
  if (str_width) fprintf(cfile,"W%d\n",width);
  if (title) fprintf(cfile,"T%s\n",title);
  if (mflag) fprintf(cfile,"M%s\n",username);
  for(i = 0; i < 4; i++) {
    if (font[i]) fprintf(cfile,"%d%s\n",i,font[i]);
  }
  {
    int	fnumber,i;
    char	**pp;
    if (*argv) {
      for(fnumber = 0, pp = argv; *pp; pp++, fnumber++) {
	construct_fd(buf,'d',fnumber);
	for(i = 0; i < copies; i++)
	  fprintf(cfile,"f%s\n",buf);
	fprintf(cfile,"U%s\n",buf);
	fprintf(cfile,"N%s\n",*pp);
      }
    } else {
      construct_fd(buf,'d',0);
      for(i = 0; i < copies; i++)
	fprintf(cfile,"f%s\n",buf);
      fprintf(cfile,"U%s\n",buf);
      fprintf(cfile,"N%s\n","stdin");
    }
    fflush(cfile);
    fseek(cfile,0,0);
    if (!REVERSE) {
      construct_fd(buf,'c',0);
      copy_file(fileno(cfile),lpd_fd,2,buf);
      fclose(cfile);
    }
    if (*argv) {
      for(fnumber = 0, pp = argv; *pp; pp++, fnumber++) {
	construct_fd(buf,'d',fnumber);
	send_file(lpd_fd,1,*pp,buf);
	if (rflag)
	  unlink(*pp);
      }
    } else {
      construct_fd(buf,'d',0);
      send_file(lpd_fd,0,"stdin",buf);
    }
    if (REVERSE) {
      construct_fd(buf,'c',0);
      copy_file(fileno(cfile),lpd_fd,2,buf);
      fclose(cfile);
    }
  }
  exit(0);
}

struct stuff {
  struct stuff	*next;
  int	size;
  char	*buf;
};
int	bufsize = 128*1024-256;
  

extern int	errno;

char *
my_getlogin()

{
  struct passwd	*pw;
  int	uid;

  if (force_username)
    return force_username;
  else {
    if ((uid = getuid()) == 0)
      return "root";
    else {
      if ((pw = getpwuid(uid)))
	return pw->pw_name;
      else
	return getlogin();
    }
  }
}

int
main(argc,argv,envp)

int argc;
char **argv;
char **envp;

{
  char	*progname;
  int	c;

  if ((progname = rindex(argv[0],'/')))
    progname++;
  else
    progname = argv[0];
  if (argv[0] && argv[1] && argv[1][0] == '-' && argv[1][1] == '.') {
    c = getopt(argc,argv,".:");
    progname = optarg;
    argc -= optind-1;
    argv += optind-1;
    optind = 1;
    argv[0] = progname;
  }
  if (strcmp(progname,"lpr") == 0) return main_lpr(argc,argv,envp);
  if (strcmp(progname,"lpq") == 0) return main_lpq(argc,argv,envp);
  if (strcmp(progname,"lprm") == 0) return main_lprm(argc,argv,envp);
  if (strcmp(progname,"lpstart") == 0) return main_lpstart(argc,argv,envp);
  if (strcmp(progname,"lpc") == 0) return main_lpc(argc,argv,envp);
  if (strcmp(progname,"lp") == 0) return main_lp(argc,argv,envp);
  return main_lpr(argc,argv,envp);
}
