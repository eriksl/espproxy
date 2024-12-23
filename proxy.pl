#!/usr/bin/perl -w

use strict;
use feature "signatures";
use threads;
use threads::shared;

require RPC::PlServer;
use Config::Simple;
use Data::Dumper;
use Try::Tiny;
use POSIX;
use JSON::Parse;
use Clone;

use Esp::IF;
use E32::EIF;

my($shared_data):shared;
my(@shared_command_queue):shared;

$EspProxy::VERSION = "0.01";
@EspProxy::ISA = qw(RPC::PlServer);

sub deep_copy_hash_5($hashref_0)
{
	my($key_1, $key_2, $key_3, $key_4, $key_5);
	my($hashref_1, $hashref_2, $hashref_3, $hashref_4);
	my(%copy);

	foreach $key_1 (keys(%$hashref_0))
	{
		$hashref_1 = \%{$hashref_0->{$key_1}};

		foreach $key_2 (keys(%$hashref_1))
		{
			$hashref_2 = \%{$hashref_1->{$key_2}};

			foreach $key_3 (keys(%$hashref_2))
			{
				$hashref_3 = \%{$hashref_2->{$key_3}};

				foreach $key_4 (keys(%$hashref_3))
				{
					$hashref_4 = \%{$hashref_3->{$key_4}};

					foreach $key_5 (keys(%$hashref_4))
					{
						$copy{$key_1}{$key_2}{$key_3}{$key_4}{$key_5} = $hashref_4->{$key_5};
					}
				}
			}
		}
	}

	return(\%copy);
}

sub deep_copy_hash_6($hashref_0)
{
	my($key_1, $key_2, $key_3, $key_4, $key_5, $key_6);
	my($hashref_1, $hashref_2, $hashref_3, $hashref_4, $hashref_5);
	my(%copy);

	foreach $key_1 (keys(%$hashref_0))
	{
		$hashref_1 = \%{$hashref_0->{$key_1}};

		foreach $key_2 (keys(%$hashref_1))
		{
			$hashref_2 = \%{$hashref_1->{$key_2}};

			foreach $key_3 (keys(%$hashref_2))
			{
				$hashref_3 = \%{$hashref_2->{$key_3}};

				foreach $key_4 (keys(%$hashref_3))
				{
					$hashref_4 = \%{$hashref_3->{$key_4}};

					foreach $key_5 (keys(%$hashref_4))
					{
						$hashref_5 = \%{$hashref_4->{$key_5}};

						foreach $key_6 (keys(%$hashref_5))
						{
							$copy{$key_1}{$key_2}{$key_3}{$key_4}{$key_5}{$key_6} = $hashref_5->{$key_6};
						}
					}
				}
			}
		}
	}

	return(\%copy);
}

sub EspProxy::get_sensor_data($dummy)
{
	return(deep_copy_hash_6($shared_data));
}

sub EspProxy::get_sensor_data_by_module_bus_id($dummy)
{
	return(deep_copy_hash_5(\%{$shared_data->{"module+bus+id"}}));
}

sub EspProxy::get_sensor_data_by_module_bus_name_type($dummy)
{
	return(deep_copy_hash_5(\%{$shared_data->{"module+bus+name+type"}}));
}

sub EspProxy::submit_command($dummy, $command)
{
	push(@shared_command_queue, shared_clone($command));
	return(0);
}

sub run_server($localport, $debug)
{
	my($server) = EspProxy->new
	(
		{
			"pidfile" => "/dev/null",
			"logfile" => "STDERR",
			"localport" => $localport,
			"localaddr" => "127.0.0.1",
			"mode" => "ithreads",
			"debug" => $debug,
			"methods" =>
			{
				"EspProxy" =>
				{
					"get_sensor_data" => 1,
					"get_sensor_data_by_module_bus_id" => 1,
					"get_sensor_data_by_module_bus_name_type" => 1,
					"submit_command" => 1,
				}
			}
		}, \@ARGV
	);

	$server->Bind();
}

sub json($json_string)
{
    $json_string =~ s/:null/:"NULL"/og;
    $json_string =~ s/:false/:"FALSE"/og;
    $json_string =~ s/:true/:"TRUE"/og;

    die("invalid json") if(!JSON::Parse::valid_json($json_string));

	try
	{
    	return(JSON::Parse::parse_json($json_string));
	}
	catch
	{
		die("invalid json");
	}
}

sub main()
{
	my(%config, $localport, $refresh, $debug, $mode, $peer, $espconfig, $stamp, $server_thread);
	my($legacy_mode);
	my($local_data);

	die("cannot read config file") if(!defined(Config::Simple->import_from($ARGV[0], \%config)));

	die("no port specified") if(!exists($config{"default.port"}));
	$localport = $config{"default.port"};

	die("no mode specified") if(!exists($config{"default.mode"}));
	$mode = $config{"default.mode"};

	die("no peer specified") if(!exists($config{"default.peer"}));
	$peer = $config{"default.peer"};

	$debug = $config{"default.debug"} || 0;
	$refresh = $config{"default.refresh"} || 30;

	if($mode eq "esp8266")
	{
		$legacy_mode = 1;
	}
	elsif($mode eq "esp32")
	{
		$legacy_mode = 0;
	}
	else
	{
		die("invalid mode specified");
	}

	$server_thread = threads->create(\&run_server, $localport, $debug);
	$server_thread->detach();

	if($legacy_mode)
	{
		$espconfig = Esp::IF::new_EspifConfig({"host" => $peer});
	}

	for(;;)
	{
		try
		{
			my($rv, %input);
			my($espif);
			my($e32if_args);
			my($e32if);
			my($json, $sensor_key, $sensor_ref, $value_index, $value_size, $value_ref, $command);

			if($legacy_mode)
			{
				$espif = new Esp::IF::Espif($espconfig);
				$rv = $espif->send("isd");

				chomp($rv);

				foreach (split(/^/om, $rv))
				{
					chomp($_);
					chomp($_);

					undef(%input);

					($input{"bus"}, $input{"id"}, $input{"address"}, $input{"name"}, $input{"type"}, $input{"value"}, $input{"unity"}) =
							m/^(?:\+ )?sensor (\d+)\/(\d+)\@([[:xdigit:]]+):\s+([^,]+),\s+([^:]+):\s+[[]([0-9.U-]+)[]]\s*([a-zA-Z%]+)?$/o;

					if(defined($input{"bus"}) && defined($input{"id"}) && defined($input{"address"}) && defined($input{"name"}) && defined($input{"type"}) && defined($input{"value"}))
					{
						$input{"module"} = 0;
						$input{"time"} = time();

						$local_data->{"module+bus+id"}{$input{"module"}}{$input{"bus"}}{$input{"id"}}{""} = Clone::clone(\%input);
						$local_data->{"module+bus+name+type"}{$input{"module"}}{$input{"bus"}}{$input{"name"}}{$input{"type"}} = Clone::clone(\%input);
					}
				}

				foreach (@shared_command_queue)
				{
					printf("command queue entry: %s\n", join(",", @{$_}));

					$rv = $espif->send(join(" ", @{$_}));

					printf("rv: %s\n", $rv);
				}

				undef($espif);
			}
			else
			{
				$e32if_args = new E32::EIF::vector_string();
				$e32if_args->push("--host");
				$e32if_args->push($peer);
				$e32if_args->push("sj");
				$e32if = new E32::EIF::E32If;
				$e32if->run($e32if_args);
				$rv = $e32if->get();

				$json = json($rv);

				foreach $sensor_key (keys(%{$json}))
				{
					$sensor_ref = \%{$json->{$sensor_key}[0]};
					$value_size = scalar(@{$sensor_ref->{"values"}});

					for($value_index = 0; $value_index < $value_size; $value_index++)
					{
						undef(%input);

						$value_ref = \%{$sensor_ref->{"values"}[$value_index]};

						if(defined($sensor_ref) && exists($sensor_ref->{"module"}) && defined($sensor_ref->{"module"}))
						{
							$input{"module"} = $sensor_ref->{"module"};
							$input{"bus"} = $sensor_ref->{"bus"};
							$input{"id"} = $sensor_ref->{"id"};
							$input{"address"} = $sensor_ref->{"address"};
							$input{"name"} = $sensor_ref->{"name"};
							$input{"type"} = $value_ref->{"type"};
							$input{"value"} = $value_ref->{"value"};
							$input{"time"} = $value_ref->{"time"};
							$input{"unity"} = $value_ref->{"unity"};

							$local_data->{"module+bus+id"}{$input{"module"}}{$input{"bus"}}{$input{"id"}}{""} = Clone::clone(\%input);
							$local_data->{"module+bus+name+type"}{$input{"module"}}{$input{"bus"}}{$input{"name"}}{$input{"type"}} = Clone::clone(\%input);
						}
					}
				}

				foreach $command (@shared_command_queue)
				{
					#printf("command queue entry: %s\n", join(",", @{$command}));

					$e32if_args = new E32::EIF::vector_string();
					$e32if_args->push("--host");
					$e32if_args->push($peer);

					foreach (@{$command})
					{
						$e32if_args->push($_);
					}

					$e32if->run($e32if_args);
					$rv = $e32if->get();

					#printf("rv: %s\n", $rv);
				}

				undef($e32if_args);
				undef($e32if);
			}

			undef(@shared_command_queue);

			#printf("* \"%s\"\n", Dumper($local_data));
		}
		catch
		{
			printf STDERR ("%s at %s\n", $_, strftime("%Y:%m:%d %H:%M", localtime(time)));
		};

		$shared_data = shared_clone($local_data);
		sleep($refresh);
	}
}

main();
