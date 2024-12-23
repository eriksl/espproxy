#!/usr/bin/perl -w

use strict;
use Data::Dumper;

require RPC::PlClient;

my(@values1) = ( "info" );
my(@values2) = ( "help", "help");

my($client) = RPC::PlClient->new("peeraddr" => "127.0.0.1", "peerport" => "2001", "application" => "EspProxy", "version" => "0.01", "user" => "none", "password" => "none");
my($rv) = $client->Call("get_sensor_data");
printf("sensors: %s\n", Dumper($rv));
printf("return: %s\n", $client->Call("submit_command", \@values1));
printf("return: %s\n", $client->Call("submit_command", \@values2));
