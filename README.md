# Tado-IF
Perl interface to Tado cloud, obtain some real-time data from your Tado heating system.

This requires to have a file /etc/tado that consists of:

```
[login]
user = <username>
password = <password>
```

Or supply the credentials to the new method (arguments 1 and 2).

Use the perl module (Tado::IF) for direct access or see the tadoif.pl for an example script.
