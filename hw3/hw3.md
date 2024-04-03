# Homework #3: Samba Server and Pi-Hole Set up

## Peter Wells, 11/11/2023

## Installing pi hole with Docker

In order to install pi hole via docker we must do a few extra steps as outlined [in pi hole's git repo](https://github.com/pi-hole/docker-pi-hole)

Obviously it will be best to change the WEBPASSWORD environment variable to something more secure. FTLCONF_LOCAL_IPV4 is the server ip address which we will use to reset our DNS server in Ubuntu. A note: I have a master docker-compose.yaml in this directory, it combines the two files here.

`docker-compose.yaml` for pi-hole modified from the quick start guide in [pi hole's repo](https://github.com/pi-hole/docker-pi-hole)
```
version: "3"

# More info at https://github.com/pi-hole/docker-pi-hole/ and https://docs.pi-hole.net/
services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    # For DHCP it is recommended to remove these ports and instead add: network_mode: "host"
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "67:67/udp" # Only required if you are using Pi-hole as your DHCP server
      - "80:80/tcp"
    environment:
      TZ: 'America/Los_Angeles'
      WEBPASSWORD: 'password'
      FTLCONF_LOCAL_IPV4: '127.1.2.3'
      WEBTHEME: "lcars"
    # Volumes store your data between container upgrades
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    #   https://github.com/pi-hole/docker-pi-hole#note-on-capabilities
    cap_add:
      - NET_ADMIN # Required if you are using Pi-hole as your DHCP server, else not needed
    restart: unless-stopped
```
<!-- EDIT: Moved the docker compose steps up due to problems with DNS! -->
1. install docker-compose with `sudo apt install -y docker-compose`
2. Copy the docker-compose.yaml file from above [(adapted from this repo)](https://github.com/pi-hole/docker-pi-hole). Note: you will need to set some variables like WEBPASSWORD manually in the file or on the system using `export` commands if you download the one from the repo.
3. Run with `sudo docker-compose up -d --force-recreate`. Note: This will probably fail to start pihole due to systemd-resolve running on port 53. Continue with the other steps and run the `docker-compose` command again. It is important to pull the image before the following steps.
4. Before editing the next files, it is useful to have backups of them. Run `sudo cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak`, `sudo cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak`, and`sudo cp /etc/resolv.conf /etc/resolv.conf.bak` to backup these files
5. We need to disable `systemd-resolve` which uses port 53 with `sudo sed -r -i.orig 's/#?DNSStubListener=yes/DNSStubListener=no/g' /etc/systemd/resolved.conf`
6. Next, change `/etc/resolv.conf` symlink to point to `/run/systemd/resolve/resolv.conf` with `sudo sh -c 'rm /etc/resolv.conf && ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf'`
7. Then restart `systemd-resolved` with `sudo systemctl restart systemd-resolved`
8. If for some reason the password you set didn't work or you need to change it you can run this command to change it inside the docker image `docker exec -ti <name_of_your_container> pihole -a -p` [(solution courtesy of this)](https://www.reddit.com/r/pihole/comments/1277bhm/how_do_i_find_my_webgui_password_after_installing/)
9. Run `sudo docker-compose up -d --force-recreate` again to get pihole up and running.
10. Once pi-hole is installed, configure clients to use it as the DNS server. Edit `/etc/netplan` (more specifically `/etc/netplan/00-installer-config.yaml`) and apply the new rules with `sudo netplan apply`. Add the the following after your interface (`eth0` in my case)

```
eth0:
    dhcp4: true
    # vvv add this  vvv
    nameservers:
        addresses: [127.1.2.3]
        # 127.1.2.3 is what I set the pihole LAN to be
```

11. Confirm it works by connecting to the pi hole via it's IP address on a web browser (defaults to 0.0.0.0, my config has it set to 127.1.2.3) and logging in with the password. Then load some websites and watch it increase the number of queries. I used firefox for this (`sudo apt install -y firefox`)
12. **NOT OPTIONAL**: If you did not set it in the docker-compose.yaml file, change your pihole's theme to LCARS menu by going to system->web interface and selecting Star Trek LCARS theme (dark) and hitting save from the web interface.

![essential menu theme](/hw3/assets/essential.png)

Troubleshooting: To reset process simply use `sudo docker ps` to see the docker containers running and `sudo docker rm <container ID>` to remove the container and start from step 9 again. Another option is to use the command `sudo docker-compose up -d --force-recreate` which will recreate the image every time. If you see on the interface that the adlist shows -2 or if you want to update the lists you will need to set the upstream dns for the pihole. This can be done from the web interface or by adding the `PIHOLE_DNS_` variable to the docker-compose file. Recommend setting it to something like 8.8.8.8. Once set, `docker exec pihole pihole -g` to update the gravity.

## Installing the Samba Server

docker-compose.yaml for Samba server
```
version: '3.4'

services:
  samba:
    image: dperson/samba
    environment:
      TZ: 'PST8PDT'
    networks:
      - default
    ports:
      - "137:137/udp"
      - "138:138/udp"
      - "139:139/tcp"
      - "445:445/tcp"
    read_only: false
    tmpfs:
      - /tmp
    restart: unless-stopped
    stdin_open: true
    tty: true
    volumes:
      - /mnt/samba_share:/mnt/samba_share
    command: '-s "samba_share;/mnt/samba_share;yes;no;no;admin" -u "admin;12345" -p'

networks:
  default:
```

For the samba server I found I had a hard time understanding how to setup the share correctly until I found [this handy guide on youtube](https://youtu.be/WypZ_I6htFc?si=-2yWG9sD1enOZrNf) which helped to demystify how samba operates.

In their explanation, they create a custom samba image and a small script to create users inside the container. It is rather involved, however so I opted to edit the one I [found here by user dperson](https://github.com/dperson/samba/blob/master/docker-compose.yml) so the configuration would fit in a simple docker-compose.yaml file.

EDIT: Running the docker-compose.yml file will actually create the `/mnt/samba_share` folder for you, chmod is still a good idea to give access to it though.

1. First, create the directory `/mnt/samba_share` for the shared folder. You may need to run `chmod -R 777 /mnt` as well so the folder is accessible to everyone.
2. Next, add the docker-compose.yaml above and run it with `sudo docker-compose up -d --force-recreate`. If you want a more secure password be sure to set it in the -s command at the end of the docker-compose file above. Currently it is set to username: `admin`, password: `12345`.
3. Now the samba server is up and running with the share name `samba_share` and the username `admin` with password `12345`.

To get the Samba share through FreeBSD's firewall I had to add some rules for the SMB ports. I added the following to `/etc/pf.conf` on the FreeBSD machine.

```
# this goes above the blocking rules
rdr pass on $ext_if proto tcp to port 445 -> $ubuntu_ip port 445
rdr pass on $ext_if proto tcp to port 139 -> $ubuntu_ip port 139

# I thought these might be needed as well, but the connection works without them, leaving them for reference
# rdr pass on $ext_if proto udp to port 137 -> $ubuntu_ip port 137
# rdr pass on $ext_if proto udp to port 138 -> $ubuntu_ip port 138

...
# put these at the end with the other blocking rules
pass out on $int_if proto tcp to port 445
pass out on $int_if proto tcp to port 139
```

4. With these rules in place you can now connect to the samba server from your host machine! On windows 10 to test try:
   - Navigating to `This PC` and right clicking on it
   - Selecting `map network drive...`
   - input the folder as `\\<free bsd ip>\samba_share`
   - hitting finish and inputting the credentials you set. username: `admin` password: `12345` by default
  
![samba server login process](/hw3/assets/sambalogin.png)
![samba server success](/hw3/assets/sambaworks.png)

Success! You can now save and edit files on the samba server directly from Windows. Simply navigate to the drive letter set to access it.

Alternatively, you can open a Powershell as administrator and run the following to test this: `net use Z: \\<ubuntu ip>\samba_share` and if the command completes successfully then the samba share worked.

![Powershell to samba command](/hw3/assets/throughBSD.png)

And that is how I set up both pi-hole as a DNS sink and a samba file sharing server for the Ubuntu VM.
