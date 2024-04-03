# Final Project

Peter Wells, 12/6/2023

## Install a containerized Gitlab instance

For this I followed the [official guide for installing Gitlab Docker images](https://docs.gitlab.com/ee/install/docker.html#install-gitlab-using-docker-compose)

1. Create the directory for gitlab to store persistent data `sudo mkdir /srv/gitlab` and ensure it has adequate permissions `sudo chomd -R 777 /srv/`
2. Add the `GITLAB_HOME` variable to `~/.bashrc` by adding the command `export GITLAB_HOME=/srv/gitlab` to the end of the file. This is the mounted volume gitlab will use to store persistent data
3. Switch to root user for the next steps. `su root`. If you don't have a password set then you will need to create one with `sudo passwd`
4. Download the `docker-compose.yml` from this repo at `/final/docker-compose.yml` and run it with `sudo docker-compose up -d`. This will create a docker container called gitlab
5. Once it's running you should be able to access it from a browser by navigating to `http://<ip address of gitlab docker container>:8929`. (this ip can be found with `sudo docker inspect gitlab` but it should be `10.9.0.6`)
6. In order to access the gitlab instance from your host pc you will need to then open up ports on FreeBSD to allow traffic to get to the gitlab instance. Do this with the following rules:
   1. Forwarding rules
      1. `rdr pass on $ext_if proto tcp to port 8929 -> $ubuntu_ip port 8929`
      2. `rdr pass on $ext_if proto tcp to port 2224 -> $ubuntu_ip port 2224`
   2. Pass rules
      1. `pass out on $int_if proto tcp to port 8929`
      2. `pass out on $int_if proto tcp to port 2224`
7. Now, you can login to the gitlab instance from your host machine from a web browser by navigating to `http://<freeBSD IP>:8929`. Note: It may take a few minutes to spin up.
8. To login as root, use the username `root` and copy the password in `/srv/gitlab/config/initial_root_password`
9. Once logged in you will want to change the password as GitLab will automatically change it in 24 hours! Go to the `user_avatar->edit profile-password` to change it
10. If you want to access the admin area do so by logging in and then navigating to `http://<freeBSD IP>:8929/admin/` while logged in as root or finding the admin area button (I couldn't find it)

![screenshot of the admin panel on Gitlab](/final/assets/gitlab_admin_area.png)

## Install a dockerized, self-hosted Bitwarden instance

For Bitwarden we are going to use [vault warden](https://hub.docker.com/r/vaultwarden/server)
Configuration [setup steps found here](https://github.com/dani-garcia/vaultwarden/wiki/Configuration-overview)

1. The docker-compose file will create a `vaultwarden` container for you but here is how to pull it manually
   1. `sudo docker pull vaultwarden/server:latest`
   2. `sudo docker run -d --name vaultwarden -v /vw-data/:/data/ -p 8888:80 vaultwarden/server:latest`
2. Once this is done, you can access the service by navigating to `http://<ip of vaultwarden container>` on the VM. (Once again, this is found with `sudo docker inspect vaultwarden`)
3. If you want to access it from the Host machine it is a similar process to GitLab. You must open port `8888` as defined in the `docker-compose.yml` file
   1. Forward rule: `rdr pass on $ext_if proto tcp to port 8888 -> $ubuntu_ip port 8888`
   2. Pass rule: `pass out on $int_if proto tcp to port 8888`
4. Then you can access the VaultWarden dashboard at `http://<freeBSD ip>:8888` on the host machine
5. Note that Before you can access this dashboard on most web browsers, you must set up HTTPS. [This link is helpful for that](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-HTTPS). It mentions setting up a reverse proxy using Caddy. I have decided to omit this for now as I am not planning on actually using this bitwarden instance and would instead set this up on a real domain. I have left the set up configuration for it in the `docker-compose.yml` file at the bottom, commented out for future reference

![screenshot of vaultwarden login screen](/final/assets/vaultwarden_login.png)

## Install a containerized ZoneMinder

For Zoneminder I used [this docker compose file](https://github.com/zoneminder-containers/zoneminder-base/blob/main/docker-compose.yml). You can see the sections added to the `docker-compose.yml` file in this repo. You will also need to download the .env file and paste it in the directory you are running the docker-compose file from. This is also included in this repo. I currently have it named `RENAMETHIS.env` in order for the gitignore to not flag it, simply change it to `.env`

1. This service will be set up with the `docker-compose.yml` file along with the others. `sudo docker-compose up -d`
2. To access it, find the ip address of the container again with `docker inspect zoneminder` and connect to it by entering that ip address into a browser on the VM. `http://<zoneminder ip address>/`
3. Once again, if you want to access this from the host machine you will need to open the port for it on the firewall. In this case port: `7979` as defined in the `docker-compose.yml` file
   1. Forward rule: `rdr pass on $ext_if proto tcp to port 7979 -> $ubuntu_ip port 7979`
   2. Pass rule: `pass out on $int_if proto tcp to port 7979`
4. Then you can access the ZoneMinder control panel via web-browser at `http://<freeBSD ip>:7979` on the host machine

![screenshot of zoneminder dashboard](/final/assets/zoneminder_console.png)

## Set up a Static Page Generator for Gitlab

### Jenkins and GitLab integration

References:

- [Installing Jenkins](https://www.cloudbees.com/blog/how-to-install-and-run-jenkins-with-docker-compose)
- [Installing Jekyll](https://benhoskins.dev/run-jekyll-in-docker-with-docker-compose/)
- [Gitlab Jenkins Plugin](https://plugins.jenkins.io/gitlab-plugin/)
- [Continuous Deployment of Jekyll Website with Jenkins](https://sketchingdev.co.uk/blog/continuous-deployment-of-jekyll-website-with-jenkins.html)

A quick note: Since writing this part of the guide, I decided to change the `docker-compose.yml` file so that Gitlab and Jenkins docker containers to have static IPs. The reason for this was that I found everytime I reset the Ubuntu VM it would assign a new ip. So anywhere that requires a specific IP will now use the following:

- GitLab container IP: `10.9.0.6:8929`
- Jenkins container IP: `10.9.0.5:8080`

#### Installing Jenkins

1. Install Jenkins via the `docker-compose.yml` file provided in `/final/`
2. Log in to Jenkins via web browser at `http://<jenkins container ip>:8080`
3. To get the password for it when logging in run this and copy it over: `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`
4. Once logged in, you will be prompted to for which plugins to install. I opted to use the community ones instead of specifying though we will need the [Gitlab Jenkins Plugin](https://plugins.jenkins.io/gitlab-plugin/). This can be installed after the fact by going to the plugin manager from the Jenkins dashboard and installing it manually.
5. Like the previous steps you will need to add port `8080` to the FreeBSD firewall if you want to access it from the host machine
   1. Forward rule: `rdr pass on $ext_if proto tcp to port 8080 -> $ubuntu_ip port 8080`
   2. Pass rule: `pass out on $int_if proto tcp to port 8080`

![screenshot of jenkins homepage](assets/jenkins_home_page.png)

#### Gitlab to Jenkins Auth

1. Create a user in Jenkins that has at minimum Job/Build permissions (this can just be the admin you set up at the start)
2. Log in and click the user name in the top right corner, then go to the ***Configure*** tab
3. Copy down the user id assigned to this user found under the ***Status*** tab
4. Under API Token click ***Add new token***, give it a name and hit generate. Be sure to save this token as it will be impossible to recover later.
5. Log in to **Gitlab** instance created earlier, we need to allow requests to the local network from webhooks and integrations. Do that by logging in as the administrator (described above) and going to the admin panel, settings, and checking `Allow requests to the local network from webhooks and integrations` under Outbound requests.
6. Next create a new user (you will have to manually approve their account from the Admin panel) and then create a new blank project.
7. Once in the project, from the left bar select ***Settings*** and the ***Webhooks*** and Create a new webhook. The URL format will be `http://USERID:APITOKEN@JENKINS_URL/project/YOUR_JOB`. Where USERID and APITOKEN are the values you saved earlier. For `JENKINS_URL` use the ip address of the container it is running on. `<ip of the container running jenkins>:8080` Do not enter anything for secret token. The `YOUR_JOB` should be set to the job you create in Jenkins, I created a blank *freestyle job* in Jenkins called build-static-site. Also disable SSL certification as we have not set that up. So for mine, it was `http://jenky:11e72f01653d7b6e7cd88f0baa7a807d8b@10.9.0.1:8080/project/build-static-site`. Be sure to select freestyle job as this is what the rest of the directions assume, see the [Gitlab Jenkins Plugin](https://plugins.jenkins.io/gitlab-plugin/) link if you want to use a pipeline.
8. When you hit `test` at the bottom, it should succeed

![screenshot showing gitlab webhook working](/final/assets/gitlab_hook_works.png)

#### Jenkins to GitLab Auth

Note: I believe this is optional. This is only used for accessing GitLab API to send the build status to GitLab. It is not used for cloning git repos. The cloning credentials should be separate.

1. Over in **GitLab**, While logged in as your user (who should be a maintainer on the repo) click the user icon in the corner again and select ***settings***
2. Go to Access Tokens and create a new api token titled something like `Jenkins-Token` (or something), expiration is optional. I opted not to expire it. Select `api` on the bottom and create the token. Be sure to**write it down as it will be inaccessible after leaving this page**.
3. Go back to the global configuration page in **Jenkins**, scroll down to ***GitLab*** and add a gitlab connection. Give it a name and for the GitLab Host URL use the ip address for the container running gitlab with the port `8929` which in my case is `http://10.9.0.6:8929`
4. Under credentials click add. Change the type to `Gitlab API Token` and paste in the value you got for `Jenkins-Token` in GitLab. Select it from the drop down and hit save
5. Click the ***test connection*** button, it should succeed

![screenshot showing jenkins api token working](/final/assets/jenkins_token_works.png)

#### Jenkins project configuration

In order to have pushes trigger a Jenkins build, we need to configure some things in Jenkins.

1. We need to edit our build project. Open the configuration window and scroll down to ***Source Code Management***
2. Here we add the Repository URL (for me was `http://10.9.0.6:8929/pwell2/static-site-generator.git`)
3. We also have to set up new credentials as for some reason it doesn't use our api token. Do this by hitting ***add*** under credentials. Choose ***Username and Password*** for Kind and set your Gitlab Username and Password here. *Note*: This feels like it should be unnecessary since we set up credentials in the section above, but the git plugin was not allowing me to select the api credentials created so I did this too as a workaround. I suspect this is probably due to using http and no ssl certificates.
4. Next we need to open the advanced tab and add a couple things. Under ***Name*** set it to `origin` and under ***Refspec*** set it to this: `+refs/heads/*:refs/remotes/origin/* +refs/merge-requests/*/head:refs/remotes/origin/merge-requests/*` Note: adding this refspec popped up an error that the refspec was invalid but it appears to work.
5. In the ***branch-specifier*** section set it to `origin/main`
6. In the ***Additional Behaviors*** click add and select ***Merge before build*** from the dropdown menu. Set name to `origin` and ***branch to merge*** to `main`

Next, we need to configure job triggers.

1. In the build triggers setting select `Build when a change is pushed to GitLab` and copy the Gitlab Webhook URL generated at the end of that selection
2. Select which events you want to trigger a build, in my case I selected Push Events, Accepted Merge Requests and Approved Merge Requests events (this is only available on GitLab Enterprise but still thought it'd be nice to have)
3. Back in **Gitlab**, create a webhook with the URL you copied from Jenkins. Be sure to select the events you want to build on. I selected `push events` and `merge request events`. For whatever reason push events didn't work if I tried to specify the main branch so I left it on `All branches` for now.
4. In order for the webhook to work, go to `**Jenkins**->Global Settings`, uncheck ***enable authentication for '/project' end-point*** and hit save
5. Under build environment, select ***Delete workspace before build starts*** and Add timestamps to the Console Output

And finally, we are able to trigger a Jenkins build from a push on GitLab!!!! I triggered these builds with the test button on the webhook in Gitlab.

![screenshot showing that a build was triggered from gitlab](/final/assets/jenkins_build_triggered.png)

### Gitlab Repo and Jenkins Job Configuration

#### Jenkins Job Configuration

Now that we are triggering builds from GitLab pushes, we need to set up the build steps to actually construct our static page.

First create an `Execute Shell` build step and put this in it. What this does is create a folder for the output file, ensures that Jekyll is properly installed and then runs `jekyll build -d ../output` which tells Jekyll to build our static site and place the result in the output folder.

```sh
echo "hello from build steps"

if !test -f ./output; then
   mkdir output
fi

if test -f ./source/index.md; then
   echo "file exists - commencing static site build"
   apt-get update
   apt-get install -y ruby-full build-essential zlib1g-dev
   gem install jekyll bundler
    
   cd ./source
   jekyll build -d ../output;
else
   echo "Missing ./source/index.md!"
fi
```

Now this is great but as soon as the build ends our site gets deleted! We need to add a post-build action as well.

Add an `Archive the Artifacts` Post-build action to this and for ***Files to archive*** input `output/**`. This will take everything in the output folder and it's subfolders and archive it for download.

Note: If we had a web server actually set up for this we could instruct instead to replace the files on the web server and update our page this way.

#### Gitlab Repo

Before Jenkins will be able to build a site, we need to set up our repo properly

1. Clone down the repo to a local machine (use the credentials for the user you set up or set up ssh keys)
2. In the root directory run `jekyll new --blank source` to create a new Jekyll project called source
3. Edit the files to create the type of site you want. Take a look at `/source/index.md` and `/source/_layouts/default.html` to get an idea
4. Push this up to the repository (which will trigger a build)

Now, Jenkins should automatically start a build and generate the static.html page!

![screenshot showing successful jenkins build with build artifacts](/final/assets/jenkins_successful_build.png)

#### Viewing the page

Since we don't have a webserver to host this on simply download the build artifacts and open index.html in a web browser. You can see I may have had  to try this a few times based on the content of my site :D

![screenshot showing the generated static site](/final/assets/static_site_displayed.png)

Whew, we did it! Thank you for a great term. I never thought I'd be setting up Jenkins but it was cool to see how that actually works from the ground up.
