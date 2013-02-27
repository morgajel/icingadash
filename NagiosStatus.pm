package NagiosStatus;
#
# NagiosStatus.pm
# Copyright (C) 2010-2011 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

our $VERSION = '0.72';

# our constructor
sub new
{
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = ();
	$self->{STATUSFILE} = shift;
	$self->{ERROR} = 1;
	$self->{ERRORMSG} = "not parsed any statusfile";
	$self->{HOSTS} = {};
	$self->{SERVICES} = {};

	$self->{HOSTS_CRITICALS} = [];

	$self->{SERVICES_WARNINGS} = [];
	$self->{SERVICES_CRITICALS} = [];

	$self->{DEBUG} = 0;

	bless($self, $class);
	return $self;
}

sub debug
{
	my $self = shift;
	$self->{DEBUG} = shift if (@_);
	return $self->{DEBUG};
}

sub _print
{
	my $self = shift;
	my $msg = shift;

	print STDERR "$msg\n" if $self->{DEBUG};
}

sub evaluate
{
	my $self = shift;

	# evaluate the hosts
	foreach my $statusobjectname (keys %{$self->{'HOSTS'}})
	{
		if ($self->{'HOSTS'}->{$statusobjectname}->{'current_state'} == 1)
		{
			push(@{$self->{'HOSTS_CRITICALS'}}, $statusobjectname);
		}
	}
	# evaluate the services
	foreach my $statusobjectname (keys %{$self->{'SERVICES'}})
	{
		if ($self->{'SERVICES'}->{$statusobjectname}->{'current_state'} == 1)
		{
			push(@{$self->{'SERVICES_WARNINGS'}}, $statusobjectname);
		}
		elsif ($self->{'SERVICES'}->{$statusobjectname}->{'current_state'} == 2)
		{
			push(@{$self->{'SERVICES_CRITICALS'}}, $statusobjectname);
		}
	}

	foreach my $TYPE ("WARNINGS", "CRITICALS")
	{
		for (my $i = (scalar @{$self->{"SERVICES_$TYPE"}})-1; $i >= 0; $i--)
		{
			my $object = $self->{SERVICES}->{$self->{"SERVICES_$TYPE"}->[$i]};
			$self->_print("Performing: SERVICE $TYPE '$object->{'host_name'}' - '$object->{'service_description'}'");

			# for a service, where the host is already down ... we won't show the alert
			if ($object->{'host_name'} && grep(/$object->{'host_name'}/, @{$self->{'HOSTS_CRITICALS'}}) >= 1)
			{
				splice(@{$self->{"SERVICES_$TYPE"}}, $i, 1);
				$self->_print("Removing: '$object->{'host_name'}' - '$object->{'service_description'}' Host is already listed");
			}
			# if it has already been acknowledged
			elsif ($object->{'problem_has_been_acknowledged'})
			{
				splice(@{$self->{"SERVICES_$TYPE"}}, $i, 1);
				$self->_print("Removing: '$object->{'host_name'}' - '$object->{'service_description'}' ACKnowledged");
			}
			# if notifications are disabled
			elsif (!$object->{'notifications_enabled'})
			{
				splice(@{$self->{"SERVICES_$TYPE"}}, $i, 1);
				$self->_print("Removing: '$object->{'host_name'}' - '$object->{'service_description'}' notifications disabled");
			}
			# soft states are ignorable too
			elsif ($object->{'current_state'} != $object->{'last_hard_state'})
			{
				splice(@{$self->{"SERVICES_$TYPE"}}, $i, 1);
				$self->_print("Removing: '$object->{'host_name'}' - '$object->{'service_description'}' SOFT State");
			}
			else
			{
				$self->_print("Adding: '$object->{'host_name'}' - '$object->{'service_description'}'");
			}
		}
	}

	for (my $i = (scalar @{$self->{'HOSTS_CRITICALS'}})-1; $i >= 0; $i--)
	{
		my $object = $self->{HOSTS}->{$self->{'HOSTS_CRITICALS'}->[$i]};
		# if it has already been acknowledged
		if ($object->{'problem_has_been_acknowledged'})
		{
			splice(@{$self->{'HOSTS_CRITICALS'}}, $i, 1);
		}
		# if notifications are disabled
		elsif (!$object->{'notifications_enabled'})
		{
			splice(@{$self->{'HOSTS_CRITICALS'}}, $i, 1);
		}
		# soft states are ignorable too
		elsif ($object->{'current_state'} != $object->{'last_hard_state'})
		{
			splice(@{$self->{'HOSTS_CRITICALS'}}, $i, 1);
		}
	}
}

sub get_alerts
{
	my $self = shift;
	my $params = shift;

	my @RETURN = ();
	foreach my $alert (@{$self->{"HOSTS_CRITICALS"}})
	{
		my %hash = ();
		$hash{'type'} = 'critical';
		foreach (@{$params})
		{
			$hash{$_} = $self->{'HOSTS'}->{$alert}->{$_};
		}
		push(@RETURN, \%hash);
	}
	foreach my $alert (@{$self->{"SERVICES_CRITICALS"}})
	{
		my %hash = ();
		$hash{'type'} = 'critical';
		foreach (@{$params})
		{
			$hash{$_} = $self->{'SERVICES'}->{$alert}->{$_};
		}
		push(@RETURN, \%hash);
	}
	foreach my $alert (@{$self->{"SERVICES_WARNINGS"}})
	{
		my %hash = ();
		$hash{'type'} = 'warning';
		foreach (@{$params})
		{
			$hash{$_} = $self->{'SERVICES'}->{$alert}->{$_};
		}
		push(@RETURN, \%hash);
	}

	return @RETURN;
}

sub parse_statusfile
{
	my $self = shift;
	my %services = ();
	if (-e $self->{STATUSFILE})
	{
		my $index = 0;
		open(FILE, $self->{STATUSFILE});
		while (<FILE>)
		{
			my $line = $_;
			chomp($line);
			$line =~ s/^\s+(.*)/$1/;
			next if $line eq "" || $line eq "}";
			$index++ if ($line =~ /.*\{$/);
			push(@{$services{$index}}, $line);
		}
		close(FILE);
		$self->{ERROR} = 0;
	}
	else
	{
		$self->{ERRORMSG} = $self->{STATUSFILE}." does not exist.";
	}

	foreach my $index (keys %services)
	{
		my $TYPENAME = "";
		my %HASH = ();
		for (my $i = 0; $i < scalar (@{$services{$index}}); $i++)
		{
			if ($i == 0 && ${$services{$index}}[$i] =~ /^(host|service)status\s\{/)
			{
				$TYPENAME = uc($1)."S";
			}
			else
			{
				if (${$services{$index}}[$i] =~ /^([\w]+)=(.*)$/)
				{
					$HASH{$1} = $2;
				}
			}
		}
		if ($TYPENAME eq "HOSTS")
		{
			$HASH{'service_description'} = "HOST";
			$self->{$TYPENAME}->{$HASH{'host_name'}} = \%HASH;
		}
		elsif ($TYPENAME eq "SERVICES")
		{
			$self->{$TYPENAME}->{"$HASH{'host_name'}_$HASH{'service_description'}"} = \%HASH;
		}
	}
}

1;
