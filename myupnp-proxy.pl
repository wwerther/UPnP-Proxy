#!/usr/bin/perl -w
# vi: set ts=4; nu: 
################# - Config Section - #############################
#
# Don't forget to set a multicast route!
# route add -net 224.0.0.0 netmask 224.0.0.0 dev <net-device>

my $debug=1;
my $config = {
	'794fdb2e-88b7-48b3-8557-1966da0a707c' => {
		'ip' => '10.16.1.15',
		'port' => 49152,
		'type' => 'mediatomb012'
	},
	'ad9d6390-b73a-43c8-a047-06eecdf9839g' => {
		'ip' => '10.16.1.15',
		'port' => 80,
		'type' => 'test2'
	},
};

my $ssdps = {

};

my $ssdpdefs= {
	'mediatomb012' => {
		'SERVER' => 'Linux/2.6.31-20-server, UPnP/1.0, MediaTomb/0.12.0',
		'LOCATION' => 'http://<ip>:<port>/description.xml',
		'NT' => [
			 'upnp:rootdevice','','urn:schemas-upnp-org:device:MediaServer:1','urn:schemas-upnp-org:service:ConnectionManager:1','urn:schemas-upnp-org:service:ContentDirectory:1'
		]
	},
	'test' => {
		'SERVER' => 'Linux/2.6.31-20-server, UPnP/1.0, TestHTTP/0.0.1',
		'LOCATION' => 'http://<ip>:<port>/description.xml',
		'NT' => [
			 'upnp:rootdevice','urn:schemas-upnp-org:device:MediaServer:1','urn:schemas-upnp-org:service:ConnectionManager:1','urn:schemas-upnp-org:service:ContentDirectory:1'
		]
	},
	
};

#
################# - Code Section - DO NOT EDIT - #################
#
use strict;
use IO::Socket::INET;
use IO::Socket::Multicast;


use Data::Dumper;


  my $socket = IO::Socket::Multicast->new(LocalPort=>49152,
                                          LocalAddr=>'10.16.1.15',
                                          ReuseAddr=>1);

  $socket->mcast_add('239.255.255.250','eth0:1');

if ($debug) {
	print "Config: \n";
	print Dumper($config);

	print "SSDP-Defs: \n";
	print Dumper($ssdpdefs);
}


foreach my $usn (keys %$config) {
	my $data=$config->{$usn};

	if ($ssdpdefs->{$data->{'type'}} ) {
		print "Found definition for ".$data->{'type'}." and USN $usn\n";

		my $defs=$ssdpdefs->{$data->{'type'}};

		my $server = $defs->{'SERVER'};
		my $location = $defs->{'LOCATION'};

		$server =~ s/<ip>/$data->{'ip'}/g;
		$server =~ s/<port>/$data->{'port'}/g;
		$location =~ s/<ip>/$data->{'ip'}/g;
		$location =~ s/<port>/$data->{'port'}/g;

		foreach my $nt (@{$defs->{'NT'}}){

			$nt="uuid:$usn" if ($nt eq '');

			print "--> $nt\n";

			my $ssdp = {
				'SERVER'=>$server,
				'LOCATION'=>$location,
				'NT'=>$nt,
				'USN'=>'uuid:'.$usn."::".$nt
			};

			$ssdp->{'USN'}='uuid:'.$usn if ($nt eq "uuid:$usn");

			push (@{$ssdps->{$usn}},$ssdp);
		};

	} else {
		print "Could not find definition for ".$data->{'type'}.". Will skip this one\n";
	}

}

if ($debug) {
	print "SSDP: \n";
	print Dumper($ssdps);
}


print "Initializing...\n";

my $mcast = IO::Socket::INET->new(
	PeerAddr  => '239.255.255.250',
	PeerPort  => 1900,
	Proto	  => 'udp',
	Blocking  => 0) 
	|| die "Can't bind to UDP multicast socket\n";

sub mysend {
	my $socket = shift;
	my $record = shift;
	my $type = shift;

	print "Sending $type for ".$record->{'USN'}."\n";

	$socket->send(	"NOTIFY * HTTP/1.1\r\n".
					"HOST: 239.255.255.250:1900\r\n".
			        "CACHE-CONTROL: max-age=1810\r\n".
			        "LOCATION: ".$record->{'LOCATION'}."\r\n".
	    		    "NT: ".$record->{'NT'}."\r\n".
	    		    "NTS: ".$type."\r\n".
	    		    "SERVER: ".$record->{'SERVER'}."\r\n".
		            "USN: ".$record->{'USN'}."\r\n"
					."\r\n");

}

sub checkalive {
	my $location = shift;
	
	return 1;
}





sub handleusn {
	my $usn = shift;
	my $message = shift || 'ssdp:byebye';
	foreach my $record (@{$ssdps->{$usn}}) {
		mysend ($mcast,$record,$message);
	}
}


sub all {
	my $msg=shift || 'ssdp:byebye';
	foreach my $usn (keys %$ssdps) {
		print "Handling $usn\n";
		handleusn($usn,$msg);
		sleep 1;
	}
}

all('ssdp:byebye');
all('ssdp:byebye');

sleep 4;
all('ssdp:alive');
all('ssdp:alive');
all('ssdp:alive');

print "Initial Broadcasts done...\n";
my $done=0;
$SIG{INT} = sub { print "Interrupt: please wait...\n"; $done=1 };
while (!$done) {
    sleep 8;
    last if ($done);
    sleep 8;
    last if ($done);
    sleep 8;
    last if ($done);
	all('ssdp:alive');
}
sleep 4;
all('ssdp:byebye');
all('ssdp:byebye');

print "...exiting.\n";
exit;
