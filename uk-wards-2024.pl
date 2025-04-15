#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use JSON::XS;
use Data::Dumper;

# A JSON containing the property "final" which points to where the combined file is
my $config = LoadJSON("config.json");

if($ARGV[0] eq "split"){

	splitAreas();

}elsif($ARGV[0] eq "combine"){

	if($ARGV[1] eq "LAD"){
		combineLAD();
	}else{
		combineRegions();
	}

}elsif($ARGV[0] eq "shift"){

	shiftMap($ARGV[1],$ARGV[2]);

}elsif($ARGV[0] eq "augment"){

	augment();

}elsif($ARGV[0] eq "ticklist"){

	#createTickList();

}

simplify();




#############################

sub msg {
	my $str = $_[0];
	my $dest = $_[1]||"STDOUT";
	
	my %colours = (
		'black'=>"\033[0;30m",
		'red'=>"\033[0;31m",
		'green'=>"\033[0;32m",
		'yellow'=>"\033[0;33m",
		'blue'=>"\033[0;34m",
		'magenta'=>"\033[0;35m",
		'cyan'=>"\033[0;36m",
		'white'=>"\033[0;37m",
		'none'=>"\033[0m"
	);
	foreach my $c (keys(%colours)){ $str =~ s/\< ?$c ?\>/$colours{$c}/g; }
	if($dest eq "STDERR"){
		print STDERR $str;
	}else{
		print STDOUT $str;
	}
}

sub error {
	my $str = $_[0];
	$str =~ s/(^[\t\s]*)/$1<red>ERROR:<none> /;
	msg($str,"STDERR");
}

sub warning {
	my $str = $_[0];
	$str =~ s/(^[\t\s]*)/$1<yellow>WARNING:<none> /;
	msg($str,"STDERR");
}

sub ParseJSON {
	my $str = shift;
	my $json = {};
	if(!$str){ $str = "{}"; }
	eval {
		$json = JSON::XS->new->decode($str);
	};
	if($@){ error("\tInvalid output.\n"); }
	return $json;
}

sub LoadJSON {
	my (@files,$str,@lines,$json);
	my $file = $_[0];
	open(FILE,"<:utf8",$file);
	@lines = <FILE>;
	close(FILE);
	$str = (join("",@lines));
	# Error check for JS variable e.g. South Tyneside https://maps.southtyneside.gov.uk/warm_spaces/assets/data/wsst_council_spaces.geojson.js
	$str =~ s/[^\{]*var [^\{]+ = //g;
	return ParseJSON($str);
}

sub makeJSON {
	my $json = shift;
	
	my $txt = JSON::XS->new->utf8->canonical(1)->pretty->space_before(0)->encode($json);
	
	$txt =~ s/   /\t/g;

	$txt =~ s/(\t{3}.*)\n/$1/g;
	$txt =~ s/\,\t{3}/\, /g;
	$txt =~ s/\t{2}\}(\,?)\n/ \}$1\n/g;
	$txt =~ s/\{\n\t{3}/\{ /g;
	
	$txt =~ s/\"\: /\"\:/g;
	$txt =~ s/\, \"/\,\"/g;
	$txt =~ s/":\{ "/":\{"/g;
	$txt =~ s/\" \},/\"\},/g;
	
	return $txt;
}

# Version 1.1.1
sub SaveJSON {
	my $json = shift;
	my $file = shift;
	my $depth = shift;
	my $oneline = shift;
	if(!defined($depth)){ $depth = 0; }
	my $d = $depth+1;
	my ($txt,$fh);
	

	$txt = JSON::XS->new->canonical(1)->pretty->space_before(0)->encode($json);
	$txt =~ s/   /\t/g;
	$txt =~ s/\n\t{$d,}//g;
	$txt =~ s/\n\t{$depth}([\}\]])(\,|\n)/$1$2/g;
	$txt =~ s/": /":/g;

	if($oneline){
		$txt =~ s/\n[\t\s]*//g;
	}

	msg("Save JSON to <cyan>$file<none>\n");
	open($fh,">:utf8",$file);
	print $fh $txt;
	close($fh);

	return $txt;
}

sub simplify {
	msg("Simplifying the content of <cyan>$config->{'final'}<none>\n");
	my ($regions,$id,$region,$fh,$d);
	my $hexjson = LoadJSON($config->{'final'});
	
	foreach $id (keys(%{$hexjson->{'hexes'}})){
		foreach $d (keys(%{$hexjson->{'hexes'}{$id}})){
			if($d ne "q" && $d ne "r" && $d ne "name" && $d ne "n" && $d ne "colour" && $d ne "RGN24CD" && $d ne "LAD24CD" && $d ne "RGN24NM" && $d ne "LAD24NM" && $d ne "lat" && $d ne "lon"){
				delete $hexjson->{'hexes'}{$id}{$d};
			}
		}
	}
	SaveJSON($hexjson,"uk-wards-2024.hexjson",2);
}

sub createTickList {
	msg("Creating tick list from <cyan>$config->{'final'}<none>\n");
	my ($lads,$id,$lad,$fh);
	my $hexjson = LoadJSON($config->{'final'});

	foreach $id (keys(%{$hexjson->{'hexes'}})){
		$lad = $hexjson->{'hexes'}{$id}{'LAD24CD'};
		$lads->{$lad} = {'name'=>$hexjson->{'hexes'}{$id}{'LAD24NM'},'region'=>$hexjson->{'hexes'}{$id}{'RGN24CD'}};
	}

	foreach $lad (sort(keys(%{$lads}))){
		msg("- [ ] [$lad](https://open-innovations.org/projects/hexmaps/editor/?https://open-innovations.github.io/uk-wards-2024/$lads->{$lad}{'region'}.hexjson) - $lads->{$lad}{'name'}\n");
	}
}

sub shiftMap {
	my $drow = shift;
	my $dcol = shift;
	msg("Shifting hexes in <cyan>$config->{'final'}<none>\n");
	my ($regions,$id,$region,$fh,$lads,$lad,$json,$file,$newtxt,$oldtxt);
	my $hexjson = LoadJSON($config->{'final'});
	
	foreach $id (keys(%{$hexjson->{'hexes'}})){

		$hexjson->{'hexes'}{$id}{'r'} += $drow;
		$hexjson->{'hexes'}{$id}{'q'} += $dcol;

	}

	# Make regions
	msg("Updating map\n");
	SaveJSON($hexjson,$config->{'final'}.".new",2);
}

sub splitAreas {
	msg("Splitting areas in <cyan>$config->{'final'}<none>\n");
	my ($regions,$id,$region,$fh,$lads,$lad,$json,$file,$newtxt,$oldtxt);
	my $hexjson = LoadJSON($config->{'final'});
	
	foreach $id (keys(%{$hexjson->{'hexes'}})){
		$region = $hexjson->{'hexes'}{$id}{'RGN24CD'};
		$lad = $hexjson->{'hexes'}{$id}{'LAD24CD'};
		if(!$regions->{$region}){
			$regions->{$region} = {'layout'=>$hexjson->{'layout'},'hexes'=>{}};
		}
		$regions->{$region}{'hexes'}{$id} = $hexjson->{'hexes'}{$id};
		if(!$lads->{$lad}){
			$lads->{$lad} = {'layout'=>$hexjson->{'layout'},'hexes'=>{}};
		}
		$lads->{$lad}{'hexes'}{$id} = $hexjson->{'hexes'}{$id};
	}
	
	# Make regions
	msg("Updating regions\n");
	foreach $region (sort(keys(%{$regions}))){
		$file = $region.".hexjson";
		$json = LoadJSON($file);
		$oldtxt = makeJSON($json);
		# Set a version
		$regions->{$region}{'version'} = ($json->{'version'} || "0.1");
		$newtxt = makeJSON($regions->{$region});
		if($oldtxt ne $newtxt){
			$regions->{$region}{'version'} = incrementVersion($regions->{$region}{'version'});
			msg("\t<yellow>$region<none> updated to version <green>$regions->{$region}{'version'}<none> in <cyan>$file<none>\n");
			SaveJSON($regions->{$region},$file,2);
		}
	}
	
	# Make LADs
	msg("Updating local authorities\n");
	foreach $lad (sort(keys(%{$lads}))){
		$file = "LAD/".$lad.".hexjson";
		$json = LoadJSON($file);
		$oldtxt = makeJSON($json);
		# Set a version
		$lads->{$lad}{'version'} = ($json->{'version'} || "0.1");
		$newtxt = makeJSON($lads->{$lad});
		if($oldtxt ne $newtxt){
			$lads->{$lad}{'version'} = incrementVersion($lads->{$lad}{'version'});
			msg("\t<yellow>$lad<none> updated to version <green>$lads->{$lad}{'version'}<none> in <cyan>$file<none>\n");
			SaveJSON($lads->{$lad},$file,2);
		}
	}
}

sub combineLAD {
	my ($tmp,$dh,$filename,$ojson,$json,$hex,$fh,$dir,$oldtxt,$newtxt);

	$ojson = LoadJSON($config->{'final'});
	$oldtxt = makeJSON($ojson);

	msg("Combining local authorities:\n");
	$dir = "./LAD/";
	$json = {'layout'=>'odd-r','hexes'=>{}};
	opendir($dh,$dir);
	while(($filename = readdir($dh))){
		if($filename =~ /[ENSW][0-9]{8}.hexjson$/){
			$tmp = LoadJSON($dir.$filename);
			foreach $hex (keys(%{$tmp->{'hexes'}})){
				$json->{'hexes'}{$hex} = $tmp->{'hexes'}{$hex};
			}
		}
	}
	closedir($dh);

	$newtxt = makeJSON($json);

	if($oldtxt ne $newtxt){
		$json->{'version'} = incrementVersion($ojson->{'version'}||"0.0");
		msg("Updated to version <green>$json->{'version'}<none> in <cyan>$config->{'final'}<none>\n");
		SaveJSON($json,$config->{'final'},2);
	}
}

sub combineRegions {
	my ($tmp,$dh,$filename,$json,$hex,$fh);
	msg("Combining regions:\n");
	$json = {'layout'=>'odd-r','hexes'=>{}};
	opendir($dh,"./");
	while(($filename = readdir($dh))){
		if($filename =~ /[ENSW][0-9]{8}.hexjson$/){
			if($filename =~ /(E12000001|E12000002|E12000003|E12000004|E12000005|E12000006|E12000007|E12000008|E12000009|N92000002|S92000003|W92000004)/){
				msg("\t<cyan>$filename<none>\n");
				$tmp = LoadJSON($filename);
				foreach $hex (keys(%{$tmp->{'hexes'}})){
					$json->{'hexes'}{$hex} = $tmp->{'hexes'}{$hex};
				}
			}
		}
	}
	closedir($dh);

	SaveJSON($json,$config->{'final'},2);
}

sub incrementVersion {
	my $v = shift;
	my @vs = split(/\./,$v);
	my $i = (@vs)-1;
	$vs[$i] = int($vs[$i])+1;
	return join(".",@vs);
}
