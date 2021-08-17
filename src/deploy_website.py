#!/usr/bin/env python3
import os

# Get path of Project directory
repoPath = os.path.dirname(__file__)
print('Path to project:' , repoPath)
sourceSitePath = repoPath + '/src/_site/'
webroot = '/var/www/html/'
copyJob = "cp -r " + sourceSitePath + "* " + webroot
subprocess.Popen(copyJob)
