use strict;
use warnings;
use feature "signatures";

use LWP::UserAgent;
use JSON::Parse;
use WWW::Form::UrlEncoded;
use Config::Tiny;

package Tado::IF;

sub _json($self, $caller, $json_string)
{
	$json_string =~ s/:null/:"NULL"/og;
	$json_string =~ s/:false/:"FALSE"/og;
	$json_string =~ s/:true/:"TRUE"/og;

	eval { JSON::Parse::assert_valid_json($json_string); };

	if($@)
	{
		$self->_set_error(sprintf("_json: %s: %s". $caller, join(" ", $@)));
		return(undef);
	}

	return(JSON::Parse::parse_json($json_string));
}

sub _get_data($self, $caller, $method, $url, $parameters = undef)
{
	my($ua, $req, $res, $data, %headers);

	$data = undef;
	$data = WWW::Form::UrlEncoded::build_urlencoded($parameters) if(defined($parameters));

	$headers{"Content-Type"} = "application/x-www-form-urlencoded; charset=UTF-8";
	$headers{"Authorization"} = sprintf("Bearer %s", $self->{"_bearer_token"}) if(defined($self->{"_bearer_token"}));

	$ua = LWP::UserAgent->new();
	$req = HTTP::Request->new($method => $url, [ %headers ], $data);
	$res = $ua->request($req);

	if(!$res->is_success)
	{
		$self->_set_error(sprintf("%s: _get_post_data: %s: %s: %s", $caller, $method, $res->status_line, $res->decoded_content));
		return(undef);
	}

	return($res->decoded_content);
}

sub update($self)
{
	my($data, $zone);

	for($zone = 0; $zone < $self->{"_zones"}; $zone++)
	{
		$data = $self->_get_data("update", "GET", sprintf("https://my.tado.com/api/v2/homes/%d/zones/%d/state", $self->{"_home_id"}, $self->get_zone_id($zone)));
		return() if(!defined($data));
		$data = $self->_json("update", $data);
		return() if(!defined($data));
		$self->{"_zone_state"}[$zone] = $data;
	}
}

sub new($class, $username = undef, $password = undef)
{
	my($self) =
	{
		"_username" =>	$username,
		"_password" =>	$password,
		"_error" =>		undef,
	};
	my($data);

	bless($self, $class);

	if(!defined($self->{"_username"}) || !defined($self->{"_password"}))
	{
		my($config) = Config::Tiny->read("/etc/tado.conf", "utf8");
		my($username) = $config->{"login"}->{"user"};
		my($password) = $config->{"login"}->{"password"};

		return($self->_set_error("new: set user and password")) if(!defined($username) || !defined($password));

		$self->{"_username"} = $username;
		$self->{"_password"} = $password;
	}

	$data = $self->_get_data("new", "GET", "https://my.tado.com/webapp/env.js");
	return($self) if(!defined($data));
	($self->{"_api_token"}) = $data =~ m/\s+clientSecret: '(\w+)'\s/o;

	my(%parameters) =
	(
		"client_id" => 		"tado-web-app",
		"grant_type" =>		"password",
		"scope" =>			"home.user",
		"username" =>		$self->{"_username"},
		"password" =>		$self->{"_password"},
		"client_secret" =>	$self->{"_api_token"},
	);

	$data = $self->_get_data("new", "POST", "https://auth.tado.com/oauth/token", \%parameters);
	return($self) if(!defined($data));
	$data = $self->_json("new", $data);
	return($self) if(!defined($data));
	$self->{"_bearer_token"} = $data->{"access_token"};

	$data = $self->_get_data("new", "GET", "https://my.tado.com/api/v1/me");
	return($self) if(!defined($data));
	$data = $self->_json("new", $data);
	return($self) if(!defined($data));
	$self->{"_user_data"} = $data;
	$self->{"_home_id"} = $data->{"homeId"};

	$data = $self->_get_data("new", "GET", sprintf("https://my.tado.com/api/v2/homes/%d", $self->{"_home_id"}));
	return($self) if(!defined($data));
	$data = $self->_json("new", $data);
	return($self) if(!defined($data));
	$self->{"_home_data"} = $data;

	$data = $self->_get_data("new", "GET", sprintf("https://my.tado.com/api/v2/homes/%d/zones", $self->{"_home_id"}));
	return($self) if(!defined($data));
	$data = $self->_json("new", $data);
	return($self) if(!defined($data));
	$self->{"_zone_data"} = $data;
	$self->{"_zones"} = scalar(@{$data});

	$self->update();

	return($self);
}

sub _set_error($self, $error)
{
	$self->{"_error"} = sprintf("Tado::IF::%s", $error);
	return($self);
}

sub get_error($self)
{
	return($self->{"_error"});
}

sub get_zone_amount($self)
{
	return($self->_set_error("get_zone_amount: incomplete object")) if(!exists($self->{"_zone_data"})) || !defined($self->{"_zone_data"});
	return($self->{"_zones"});
}

sub get_zone_id($self, $zone)
{
	return($self->_set_error("get_zone_id: incomplete object")) if(!exists($self->{"_zone_data"})) || !defined($self->{"_zone_data"});
	return($self->{"_zone_data"}[$zone]{"id"});
}

sub get_zone_name($self, $zone)
{
	return($self->_set_error("get_zone_name: incomplete object")) if(!exists($self->{"_zone_data"})) || !defined($self->{"_zone_data"});
	return($self->{"_zone_data"}[$zone]{"name"});
}

sub get_zone_active($self, $zone)
{
	return($self->_set_error("get_zone_active: incomplete object")) if(!exists($self->{"_zone_state"}) || !defined($self->{"_zone_state"}));
	return($self->{"_zone_state"}[$zone]{"setting"}{"power"} eq "ON");
}

sub get_zone_power($self, $zone)
{
	return($self->_set_error("get_zone power: incomplete object")) if(!exists($self->{"_zone_state"}) || !defined($self->{"_zone_state"}));
	return($self->{"_zone_state"}[$zone]{"activityDataPoints"}{"heatingPower"}{"percentage"});
}

sub get_zone_temperature($self, $zone)
{
	return($self->_set_error("get_zone temperature: incomplete object")) if(!exists($self->{"_zone_state"}) || !defined($self->{"_zone_state"}));
	return($self->{"_zone_state"}[$zone]{"sensorDataPoints"}{"insideTemperature"}{"celsius"});
}

sub get_zone_humidity($self, $zone)
{
	return($self->_set_error("get_zone humidity: incomplete object")) if(!exists($self->{"_zone_state"}) || !defined($self->{"_zone_state"}));
	return($self->{"_zone_state"}[$zone]{"sensorDataPoints"}{"humidity"}{"percentage"});
}

sub dump_header($self)
{
	return(sprintf("zone id name               active power temperature humidity\n"));
}

sub dump($self)
{
	my($data, $zone, $zones);

	$zones = $self->get_zone_amount();

	for($zone = 0; $zone < $zones; $zone++)
	{
		$data .= sprintf("%4d %2d %-18s %6d %4d%% %11.1f %7d%%\n",
				$zone,
				$self->get_zone_id($zone),
				$self->get_zone_name($zone),
				$self->get_zone_active($zone),
				$self->get_zone_power($zone),
				$self->get_zone_temperature($zone),
				$self->get_zone_humidity($zone));
	}

	return($data);
}

1;
