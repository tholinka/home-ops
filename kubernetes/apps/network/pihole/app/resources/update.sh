#!/bin/bash

set -Eeuo pipefail

if [ -f "/etc/pihole/gravity.db" ]; then
	echo "houskeeping - vacuuming gravity.db"
	pihole-FTL sql /etc/pihole/gravity.db "VACUUM;" || true
else
	# run gravity to cause db to get created
	echo "creating gravity db"
	pihole -g
fi

if [ -f "/etc/pihole/pihole-FTL.db" ]; then
	echo "houskeeping - vacuuming pihole-FTL.db"
	pihole-FTL sql /etc/pihole/pihole-FTL.db "VACUUM;" || true
fi

### Allowlist items
# new sqlite approach based for PiHole v6
echo;
echo "Prepping allowlists"
echo "https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/whitelist.txt
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/optional-list.txt
https://raw.githubusercontent.com/anudeepND/whitelist/master/domains/referral-sites.txt
https://tholinka.github.io/projects/hosts/allowlist" | sort > /tmp/allow.list

echo "getting current allowlists"
pihole-FTL sql /etc/pihole/gravity.db "SELECT address FROM adlist WHERE type=1" | sort > /tmp/current-allow.list

to_remove=$(comm -23 /tmp/current-allow.list /tmp/allow.list)
echo "Removing lists not in the combined allow lists from db: $to_remove"
echo "$to_remove" |
xargs -I{} pihole-FTL sql /etc/pihole/gravity.db "SELECT id FROM adlist WHERE address='{}' AND type=1;" |
xargs -I{} pihole-FTL sql /etc/pihole/gravity.db "DELETE FROM adlist_by_group WHERE adlist_id='{}'; DELETE FROM gravity WHERE adlist_id='{}'; DELETE FROM adlist WHERE id='{}';"

to_add="$(comm -13 /tmp/current-allow.list /tmp/allow.list)"
echo "Inserting new allow lists into db: $to_add"
echo "$to_add" | xargs -I{} pihole-FTL sql /etc/pihole/gravity.db "INSERT INTO adlist (address, comment, enabled, type) VALUES ('{}', 'allowlist, added $(date +%F)', 1, 1);"

echo "Done with allowlist"

### Deny list items
# new sqlite approach based on https://discourse.pi-hole.net/t/blocklist-management-in-pihole-v5/31971/9
echo;
echo "getting current adlists"
pihole-FTL sql /etc/pihole/gravity.db "SELECT address FROM adlist WHERE type=0" | sort > /tmp/current.list

echo "Downloading adlist from wally3k.firebog.net"
curl "https://v.firebog.net/hosts/lists.php?type=tick" | sort > /tmp/firebog.list

echo "Adding tholinka.github.io tracking lists"

echo "https://tholinka.github.io/projects/hosts/wintracking/normal
https://tholinka.github.io/projects/hosts/hosts" | sort > /tmp/tholinka.list

cat /tmp/firebog.list /tmp/tholinka.list | sort > /tmp/combined.list

to_remove="$(comm -23 /tmp/current.list /tmp/combined.list)"
echo "Removing lists not in the combined lists from db: $to_remove"

echo "$to_remove" |
xargs -I{} pihole-FTL sql /etc/pihole/gravity.db "SELECT id FROM adlist WHERE address='{}' AND type=0;" |
xargs -I{} pihole-FTL sql /etc/pihole/gravity.db "DELETE FROM adlist_by_group WHERE adlist_id='{}'; DELETE FROM gravity WHERE adlist_id='{}'; DELETE FROM adlist WHERE id='{}'"

to_add="$(comm -13 /tmp/current.list /tmp/firebog.list)"
echo "Inserting new firebog lists into db: $to_add"
echo "$to_add" | xargs -I{} pihole-FTL sql /etc/pihole/gravity.db "INSERT INTO adlist (address, comment, enabled, type) VALUES ('{}', 'firebog, added $(date +%F)', 1, 0);"

to_add="$(comm -13 /tmp/current.list /tmp/tholinka.list)"
echo "Inserting new tholinka.github.io lists into db: $to_add"
echo "$to_add" | xargs -I{} pihole-FTL sql /etc/pihole/gravity.db "INSERT INTO adlist (address, comment, enabled, type) VALUES ('{}', 'tholinka.github.io, added $(date +%F)', 1, 0);"

echo;
echo "Updating pihole-FTL config"

pihole-FTL --config misc.etc_dnsmasq_d true
pihole-FTL --config dns.blockESNI false
pihole-FTL --config dns.domain.name internal
pihole-FTL --config webserver.domain "pihole.tholinka.dev"
pihole-FTL --config dns.revServers '["true,192.168.0.0/16,192.168.20.1,internal"]'
pihole-FTL --config dns.reply.host.force4 true
pihole-FTL --config dns.reply.host.IPv4 192.168.21.6
pihole-FTL --config dns.reply.blocking.force4 true
pihole-FTL --config dns.reply.blocking.IPv4 192.168.21.6
pihole-FTL --config misc.nice -999
pihole-FTL --config misc.check.load false
pihole-FTL --config dns.ignoreLocalhost true
pihole-FTL --config ntp.ipv4.active false
pihole-FTL --config ntp.ipv6.active false
pihole-FTL --config ntp.sync.active false
pihole-FTL --config database.maxDBdays 7 # default is 91, keep db size smaller
pihole-FTL --config database.network.expire 7
