# ShinyProxy

## shinyproxy setup

Follow the [shinyproxy Getting Started Guide](https://www.shinyproxy.io/getting-started/).

Here is a quick documentation and a few useful hints that were not that clear from the guide:

1. Install ShinyProxy
     - `wget https://www.shinyproxy.io/downloads/shinyproxy_2.3.0_amd64.deb`
     - `sudo apt install ./shinyproxy_2.3.0_amd64.deb`
2. Connect ShinyProxy to the docker daemon
     - `cd /etc/systemd/system`
     - `sudo mkdir docker.service.d`
     - `sudo vi override.conf`
     - add the following:

```
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H unix:// -D -H tcp://127.0.0.1:2375
```

3. Reload the configuration and restart docker via

```
sudo systemctl daemon-reload
sudo systemctl restart docker
```

4. Check for any other docker containers running if everything is still fine.
5. Create the docker-image for the 
5. Create a config file: `sudo vi /etc/shinyproxy/application.yml` with the content of [application.yml](shinyproxy/application.yml)

6. Add a firewall rule for `8080` to be accessible: `sudo ufw allow 8080`
7. *You may want to check if `/etc/systemd/system/docker.service.d/override.conf` exists now. When implementing it on our VPS server, it disappeared for some reason and I had to re-run the restart commands after adding it again.*
8. Restart the `shinyproxy` service via `sudo service shinyproxy restart` after changes to the `application.yml` file.
