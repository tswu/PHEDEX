package PHEDEX::Web::DataService;

use warnings;
use strict;

use CGI qw(header path_info url param Vars remote_host user_agent request_method);

use PHEDEX::Web::Config;
use PHEDEX::Web::Core;
use PHEDEX::Core::Timing;
use PHEDEX::Core::Loader;
use PHEDEX::Web::Format;
use PHEDEX::Web::Util;

our ($TESTING, $TESTING_MAIL);

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %h = @_;

  my $self;
  map { $self->{$_} = $h{$_}  if defined($h{$_}) } keys %h;

  # Read PhEDEx web server configuration
  my $config_file = $self->{PHEDEX_SERVER_CONFIG} ||
		       $ENV{PHEDEX_SERVER_CONFIG} ||
    die "ERROR:  Web page config file not set (PHEDEX_SERVER_CONFIG)";

  my $dev_name = $self->{PHEDEX_DEV_NAME} || $ENV{PHEDEX_DEV_NAME};

  my $config = PHEDEX::Web::Config->read($config_file, $dev_name);
  $self->{CONFIG} = $config;
  $self->{CONFIG_FILE} = $config_file;

  # Set debug mode
  $TESTING = $$config{TESTING_MODE} ? 1 : 0;
  $TESTING_MAIL = $$config{TESTING_MAIL} || undef;

  eval "use CGI::Carp qw(fatalsToBrowser)" if $TESTING;

  bless $self, $class;
  return $self;
}

sub handler
{
    local $| = 1;
    my $r = shift;
    # warn "environment: ", join(' ', map { "$_=$ENV{$_}\n\n" } keys %ENV), "\n";
    my $service = PHEDEX::Web::DataService->new(REQUEST_HANDLER=>$r);
    my $result = $service->invoke();
    if (defined $result)
    {
        my ($error, $message) = PHEDEX::Web::Util::decode_http_error($result);
        my $error_document = PHEDEX::Web::Util::error_document( $error, $message);
        if ($error_document)
        {
            $r->custom_response($error, $error_document);
        }
        $r->status($error);
        return $error;
    }
    return Apache2::Const::OK;
}

sub get_apache_params
{
    my ($self,$r) = @_;
    my $h = $r->headers_in();
#   my $s = $r->server();
    $self->{XForwardedHost} = $h->{'X-Forwarded-Host'};	# e.g. cmswttest.cern.ch
    $self->{CMSRequestURI}  = $h->{'CMS-Request-URI'};	# e.g. /phedex/dev2/datasvc/perl/prod/bounce
}

sub invoke
{
  my $self = shift;

  # Interpret the trailing path suffix: /FORMAT/DB/API?QUERY
  my $path = path_info() || "xml/prod";

  my ($format, $db, $call) = ("xml", "prod", undef);
  $format = $1 if ($path =~ m!\G/([^/]+)!g);
  $db =     $1 if ($path =~ m!\G/([^/]+)!g);
  $call =   $1 if ($path =~ m!\G/(.+)$!g);

  # Print documentation and exit if we have the "doc" path
  if ($format eq 'doc') {
      $self->print_doc();
      return;
  }

  if ($format eq 'combo') {
      return comboLoader($self);
  }

  my $type;
  if    ($format eq 'xml')  { $type = 'text/xml'; }
  elsif ($format eq 'json') { $type = 'text/javascript'; }
  elsif ($format eq 'perl') { $type = 'text/plain'; }
  else {
      &error($format, "Unsupported format '$format'");
      return;
  }

  if (!$call) {
      &error($format, "API call was not defined.  Correct URL format is /FORMAT/INSTANCE/CALL?OPTIONS");
      return;
  }

  my $http_now = &formatTime(&mytimeofday(), 'http');

  # Get the query string variables. Protect against bad client-code with undefined argument-values
  my @args = Vars();
  if ( scalar(@args)%2 ) {
    &error($format,"Malformed arguments (odd number of elements for hash)");
    return;
  }
  my %args = @args;
# Reformat multiple value variables into name => [ values ]
  foreach my $key (keys %args) {
      my @vals = split("\0", $args{$key});
      $args{$key} = \@vals if ($#vals > 0);
  }

  # create the core
  my $config = $self->{CONFIG};
  my $core;
  
  eval {
      $core = new PHEDEX::Web::Core(CALL => $call,
				    VERSION => $config->{VERSION},
				    DBCONFIG => $config->{INSTANCES}->{$db}->{DBCONFIG},
				    INSTANCE => $db,
				    REQUEST_URL => url(-full=>1, -path=>1),
				    REMOTE_HOST => remote_host(), # TODO:  does this work in reverse proxy?
                                    REQUEST_METHOD => request_method(),
				    USER_AGENT => user_agent(),
				    DEBUG => 0, # DEBUG printout screws the returned data structure
				    CONFIG_FILE => $self->{CONFIG_FILE},
				    CONFIG => $self->{CONFIG},
				    CACHE_CONFIG => $config->{CACHE_CONFIG} || {},
				    SECMOD_CONFIG => $config->{SECMOD_CONFIG},
				    AUTHZ => $config->{AUTHZ},
                                    REQUEST_HANDLER => $self->{REQUEST_HANDLER}
				    );
  };
  if ($@) {
      &error($format, "failed to initialize data service API '$call':  $@");
      return;
  }

  my %cache_headers;
  unless (param('nocache')) {
      # getCacheDuration needs re-implementing.
      my $duration = $core->getCacheDuration();
      $duration = 300 if !defined $duration;
      %cache_headers = (-Cache_Control => "public, must-revalidate, max-age=$duration",
		        -Date => $http_now,
		        -Last_Modified => $http_now,
		        -Expires => "+${duration}s");
      warn "cache duration for '$call' is $duration seconds\n" if $TESTING;
  }

  my $result = $core->prepare_call($format, %args);
  if ($result)
  {
      &error($format, $result);
      return;
  }

  # handle cookie(s) here
  if ($core->{SECMOD}->{COOKIE})
  {
      print header(-type => $type, -cookie => $core->{SECMOD}->{COOKIE}, %cache_headers );
  }
  else
  {
      print header(-type => $type, %cache_headers );
  }
  return $core->call($format, %args);
}

# For printing errors before we know what the error format should be
sub xml_error
{
    my $msg = shift;
    print header(-type => 'text/xml');
    &PHEDEX::Web::Format::error(*STDOUT, 'xml', $msg);
}

sub error
{
    my ($format, $msg) = @_;
    my $type;
    if    ($format eq 'xml')  { $type = 'text/xml'; }
    elsif ($format eq 'json') { $type = 'text/javascript'; }
    elsif ($format eq 'perl') { $type = 'text/plain'; }
    else # catch all
    {
        $type = 'text/xml';
        $format = 'xml';
    }

    print header(-type => $type);
    &PHEDEX::Web::Format::error(*STDOUT, $format, $msg);
}

sub print_doc
{
    my $self = shift;
    chdir '/tmp';
    my $service_path = $self->{CONFIG}{SERVICE_PATH};
    my $call = path_info();
    $call =~ s%^/doc/$%%;
    $call =~ s%^/doc%%;
    $call =~s%\?.*$%%;
    $call =~s%^/+%%;
    $call =~s%/+$%%;
    $call =~s%//+%/%;

    my $duration = 3600;
    my $http_now = &formatTime(&mytimeofday(), 'http');
    my %cache_headers =(-Cache_Control => "public, must-revalidate, max-age=$duration",
		        -Date => $http_now,
		        -Last_Modified => $http_now,
		        -Expires => "+${duration}s");
    print header(-type => 'text/html',%cache_headers);
    my ($module,$module_name,$loader,@lines,$line);
    $loader = PHEDEX::Core::Loader->new ( NAMESPACE => 'PHEDEX::Web::API' );
    $module_name = $loader->ModuleName($call);
    $module = $module_name || 'PHEDEX::Web::Core';

    # This bit is ugly. I want to add a section for the commands known in this installation,
    # but that can only be done dynamically. So I have to capture the output of the pod2html
    # command and print it, but intercept it and add extra stuff at the appropriate point.
    # I also need to check that I am setting the correct relative link for the modules.
    @lines = `perldoc -m $module |
                pod2html --header -css /phedex/datasvc/static/phedex_pod.css`;

    my ($commands,$count,$version);
    $version = $self->{CONFIG}{VERSION} || '';
    $version = '&nbsp;(v.' . $version . ')' if $version;
    $count = 0;
    foreach $line ( @lines ) {
        if ( $line =~ m%^</head>% ) {
          my $meta_tag = '<meta name="PhEDEx-tag" content="PhEDEx-datasvc ' . $self->{CONFIG}{VERSION} . '" />';
          print $meta_tag,"\n";
        }
        next if $line =~ m%<hr />%;
	if ( $line =~ m%<span class="block">% ) {
	  $line =~ s%</span>%$version</span>%;
	}
        if ( $line =~ m%^<table% ) {
	    $count++;
	    if ( $count != 2 ) { print $line; next; }
	    print qq{
		<h1><a name='See Also'>See Also</a></h1>
		<p>
		Documentation for the commands known in this installation<br>
		<br/>
		<table>
		<tr> <td> Command </td> <td> Module </td> </tr>
		};

	    $commands = $loader->Commands();
	    foreach ( sort keys %{$commands} ) {
		$module = $loader->ModuleName($_);
		print qq{
		     <tr>
  		     <td><strong>$_</strong></td>
		     <td><a href='$service_path/doc/$_'>$module</a></td>
		     </tr>
		    };
	    }
	    print qq{
		</table>
		</p>
		<br/>
		and <a href='.'>PHEDEX::Web::Core</a> for the core module documentation<br/>
		<br/>
		};
        }
        print $line;
    }
}

# comboLoader($core)
sub comboLoader
{
    my $core = shift;

    # Where do I get DocumentRoot for ApplicationServer ?
    my $root = $core->{REQUEST_HANDLER}->document_root();

    my %args = Vars();
    my $files = $args{f};
    if (not $files)
    {
        return PHEDEX::Web::Util::http_error(204, undef);
    }

    my @file = split(/,/, $files);

    # resolve absolute path
    my @efiles = map { ($_ =~ m!^/!)? $root . $_ : $root . '/' . $_ } @file;

    # check suffix and consistency
    my @token = split('\.', $file[0]);
    my $type = $token[$#token];
    if (not ($type eq 'css' or $type eq 'js'))
    {
        return PHEDEX::Web::Util::http_error(415, "unknown type $file[0]. Only *.css or *.js are supported.");
    }

    my (@wrong_type, @not_found);
    my $idx = 0;
    # print Dumper(\@efiles);
    foreach (@file)
    {
        @token = split('\.', $_);
        if ($token[$#token] ne $type)
        {
            push @wrong_type, $_;
        }
    
        if (! -r $efiles[$idx])
        {
            push @not_found, $_;
        }
        $idx++;
    }

    if (@wrong_type)
    {
        my $msg = qq{Wrong file type: (looking for *.$type)<br>} . join("<br>", @wrong_type);
        return PHEDEX::Web::Util::http_error(415, $msg);
    }

    if (@not_found)
    {
        my $msg = qq{Not found:<br>} . join("<br>", @not_found);
        return PHEDEX::Web::Util::http_error(404, $msg);
    }

    #suppose everything is fine

    $type = "text/" . (($type eq "js")?"javascript":$type);

    # print header
    print header(-type => $type);
    # read the files
    foreach (@efiles)
    {
        open FILE, $_;
        while (<FILE>)
        {
            print $_;
        }
    }
}

1;
