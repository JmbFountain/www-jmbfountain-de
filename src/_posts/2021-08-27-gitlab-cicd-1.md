---
layout: post
title: "Setting up Gitlab CI/CD"
categories: blog
author:
- Johannes
meta: "NATHAN, gitlab, git, docker, cicd, devops"
---
My next step of optimizing my homelab (I am lazy, after all) was in building a functional ci/cd environment. Foolish as I am, I decided to start with my website.

My current Website is statically generated using Jekyll. As a Theme I just stuck with Minima after doing a few modifications, namely reducing the content padding on the sides (I really dislike the huge white bars of nothing, my guess is they developed after people saw 16:9 screens and thought "look, how many more ads we can put on this").

## **Part 1: Getting started**

## First experiments
So, foolishly, I decided to use it as an apparently easy first start. My goal was to get a container out of it that I could just deploy to k3s.For me, the logical steps would be the following:
* take a baseline webserver image, e.g. nginx/latest
* install ruby, jekyll, minima on it
* build the website
* move the assets to the webroot
* remove everything I used to build
* push the Image to Gitlabs container registry

Starting with the Dockerfile, I drafted up something like this:
```Dockerfile
FROM nginx:latest
apt-get install ruby-full build-essential zlib1g-dev -y
gem install jekyll bundler
jekyll clean
jekyll build
COPY src/_site/ /usr/share/nginx/html/
RUN chmod -R 555 /usr/share/nginx/html
apt purge ruby-full build-essential zlib1g-dev -y
```

## Second attempt
However, for whatever reason, I couldn't get this to work (If you have an idea, contact me).
So. I decided to split this into seperate jobs, building the Website files with the official jekyll-image and then using the build artifacts feature to then create a nginx-image with them in the webroot. At this stage, I don't really care about ssl yet, since I'll likely hand it over either to HAproxy or a k3s loadbalancer.

![image-title-here](/images/blog/2021-08-26-gitlab-pipelines.png){:class="img-responsive"}

Okay, at least the pipeline in principle works, and it creates a website. The Issue with the second step largely stems from my peculiar setup: I have a privileged lxc container with nesting enabled as my docker-focused runner. Originally, I just installed one runner on it, with the docker executor. However, this gave me numerous problems with building the container:

### First error:
```
error during connect: Post "http://docker:2375/v1.24/auth": dial tcp: lookup docker on 192.168.178.1:53: no such host
Cleaning up file based variables 00:02
ERROR: Job failed: exit code 1
```

Turns out I need to use the docker-in-docker image, which also needs TLS and privileged modus.
Fixed it, and:

### Second error:
```
ERROR: Preparation failed: Error response from daemon: OCI runtime create failed: container_linux.go:380: starting container process caused: process_linux.go:545: container init caused: process_linux.go:508: setting cgroup config for procHooks process caused: failed to write "a *:* rwm": write /sys/fs/cgroup/devices/docker/4d49d370f311465c887cbda64b69a84803606503586a571d38a85306714d08dd/devices.allow: operation not permitted: unknown (docker.go:392:0s)
```

And LXC containers, even privileged ones, can't edit cgroups. 

## Changing tactic
I decided that to best circumvent this docker-in-docker thing I'd just register another runner on the same container that uses shell as an executor, which would then just execute a `docker build`-command. This somehow gives me an even less useful error ("ERROR: Job failed: exit status 1")

At the end of this stage, my .gitlab-ci.yml looks like this:

```yaml
stages:
    - compile
    - container-build

jekyll-build:
    stage: compile
    image: jekyll/builder
    tags:
        - docker
    script:
        - cd src/
        - jekyll clean
        - jekyll build
    artifacts:
        paths: 
            - src/_site/
        name: "webroot"

container-build:
    stage: container-build
    tags:
        - docker-builder
    dependencies:
        - jekyll-build
    before_script:
        - docker info
        - docker login -u cicd-container -p <TOKEN> gitlab.vj.home:5050
    script:
        - docker build -t "gitlab.vj.home:5050/johannes/www-jmbfountain-de:${CI_BUILD_REF}" .
        - docker tag gitlab.vj.home:5050/johannes/www-jmbfountain-de:${CI_BUILD_REF} "gitlab.vj.home:5050/johannes/www-jmbfountain-de:latest"
        - docker push gitlab.vj.home:5050/johannes/www-jmbfountain-de:${CI_BUILD_REF}
        - docker push gitlab.vj.home:5050/johannes/www-jmbfountain-de:latest

```
_(The token is hard-coded in this iteration, after I get it working I can still delete it, and replace it with a safer alternative)_

## **Part 2: Working CI**
_(this was originally a second post, but I decided to merge it for readability)_

.gitlab-ci.yml:
```yaml 
stages:
    - compile
    - container-build

jekyll-build:
    stage: compile
    image: jekyll/builder
    tags:
        - docker
    script:
        - cd src/
        - jekyll clean
        - jekyll build
    artifacts:
        paths: 
            - src/_site/
        name: "webroot"

container-build:
    stage: container-build
    tags:
        - docker-builder
    dependencies:
        - jekyll-build
    before_script:
        - unset cd
        - docker info
        - echo "$CI_DEPLOY_USER $CI_DEPLOY_PASSWORD $CI_REGISTRY"
        - docker login -u $CI_DEPLOY_USER -p $CI_DEPLOY_PASSWORD $CI_REGISTRY
    script:
        - docker build -t $CI_REGISTRY/johannes/www-jmbfountain-de .
        - docker push $CI_REGISTRY/johannes/www-jmbfountain-de

```

So what did I do to fix this? Basically I read through the docs for login/auth for three hours and then figured out I should use a Deployment-Token called "gitlab-deploy-token", and login using `docker login -u $CI_DEPLOY_USER -p $CI_DEPLOY_PASSWORD $CI_REGISTRY`. Now, it's time to do the cd part of CI/CD, deploying the website to Kubernetes. However, to get that part done properly, I'll have to first get my new network running, so there will be no more stuff like this for a while.

## **Part 3: Automatic Deployment**

After first deciding to leave the Deployment aspect until I had Kubernetes running in my final environment, I decided to just hack together a small change that would make it possible to use this Pipeline for "Production" already: copy the changed files to the current webserver via ssh.

```yaml
deploy-lxc:
    stage: deploy
    tags:
        - docker-builder
    dependencies:
        - jekyll-build
    script:
        - scp -r src/_site/* root@jmb-web-01:/var/www/html/

```

And done! Now I can just write a blog post, commit & push to gitlab and it automatically ends up on my blog.