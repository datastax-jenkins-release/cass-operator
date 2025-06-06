#!/bin/sh
if [[ ! $0 == scripts/* ]]; then
    echo "This script must be run from the root directory"
    exit 1
fi

if [ "$#" -lt 1 ]; then
    echo "Usage: scripts/pre-release-process.sh newTag [prevTag]"
    echo ""
    echo "If prevTag is not set, it will default to the latest tag in the repository"
    echo "usage of prevTag is required when releasing a patch version from a branch"
    exit
fi

CURRENT_BRANCH=$(git branch --show-current)

if [[ $CURRENT_BRANCH != "master" && -z "$2" ]]; then
    echo "You must provide a prevTag when releasing from a branch"
    exit 1
fi

TAG=$1
PREVTAG=$(git describe --abbrev=0 --tags)
IMG=cr.k8ssandra.io/k8ssandra/cass-operator:${TAG}

if [ ! -z "$2" ]; then
    PREVTAG=$2
fi

# Ensure kustomize is installed
make kustomize

KUSTOMIZE=$(pwd)/bin/kustomize

# Modify CHANGELOG automatically to match the tag
sed -i '' -e "s/## unreleased/## $TAG/" CHANGELOG.md

# Modify README to include proper installation refs
sed -i '' -e "s/$PREVTAG/$TAG/g" README.md

# Modify config/manager/kustomization.yaml to have proper newTag for cass-operator
cd config/manager && $KUSTOMIZE edit set image controller=$IMG && cd -

# Modify config/manager/image_config.yaml to have proper version for server-system-logger
LOG_IMG=k8ssandra/system-logger:${TAG} yq eval -i '.images.system-logger = "cr.k8ssandra.io/" + env(LOG_IMG)' config/manager/image_config.yaml

# Add prefixes to image_config if not already set
CLIENT_VALUE=$(yq '.images.k8ssandra-client' config/manager/image_config.yaml)

if [[ ! $CLIENT_VALUE == cr.k8ssandra.io* ]]; then
    # Add cr.k8ssandra.io prefixes
    yq eval -i '.images.k8ssandra-client |= "cr.k8ssandra.io/" + .' config/manager/image_config.yaml
    yq eval -i '.defaults.cassandra.repository |= sub("ghcr.io/", "")' config/manager/image_config.yaml
    yq eval -i '.defaults.cassandra.repository |= "cr.k8ssandra.io/" + .' config/manager/image_config.yaml

    # Add cr.dstx.io prefixes
    yq eval -i '.images.config-builder |= "cr.dtsx.io/" + .' config/manager/image_config.yaml
    yq eval -i '.defaults.dse.repository |= "cr.dtsx.io/" + .' config/manager/image_config.yaml
fi

# Modify the controller

# Now add everything and create a commit + tag
git add CHANGELOG.md
git add README.md
git add config/manager/kustomization.yaml
git add config/manager/image_config.yaml

git commit -m "Release $TAG"
git tag -a $TAG -m "Release $TAG"
