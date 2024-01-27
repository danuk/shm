#!/bin/bash

helm package k8s-shm --destination ./docs
helm repo index docs --url https://danuk.github.io/shm

