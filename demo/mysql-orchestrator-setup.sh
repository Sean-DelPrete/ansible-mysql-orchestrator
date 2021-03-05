#!/bin/bash

export ANSIBLE_PLAYBOOK=/usr/bin/ansible-playbook

# Setup inital DB
$ANSIBLE_PLAYBOOK ../playbooks/playbook-mysql-orchestrator-setup.yml -i ../hosts/hosts
