#!/bin/bash

BASE_REF=${1:-main}
GO_VER=$(sed -En 's/^go (.*)$/\1/p' "go.mod")
OLDIFS="${IFS}"
IFS='.' MAX_VER=(${GO_VER})
IFS="${OLDIFS}"

if [ ${#MAX_VER[*]} -ne 3 -a ${#MAX_VER[*]} -ne 2 ]; then
    echo "Invalid go version: ${GO_VER}"
    exit 1
fi

GO_MAJOR=${MAX_VER[0]}
GO_MINOR=${MAX_VER[1]}
GO_PATCH=${MAX_VER[2]}

RETCODE=0

check_version () {
    whole=$1
    file=$2
    OLDIFS="${IFS}"
    IFS='.' ver=(${whole})
    IFS="${OLDIFS}"

    if [ ${#ver[*]} -eq 2 ] ; then
        if [ ${ver[0]} -gt ${GO_MAJOR} ] ; then
            echo "Bad golang version ${whole} in ${file} (expected ${GO_VER} or less)"
            return 1
        fi
        if [ ${ver[1]} -gt ${GO_MINOR} ] ; then
            echo "Bad golang version ${whole} in ${file} (expected ${GO_VER} or less)"
            return 1
        fi
        echo "Version ${whole} in ${file} is good"
        return 0
    fi
    if [ ${#MAX_VER[*]} -eq 2 ]; then
        echo "Bad golang version ${whole} in ${file} (expecting only major.minor version)"
        return 1
    fi
    if [ ${#ver[*]} -ne 3 ] ; then
        echo "Badly formatted golang version ${whole} in ${file}"
        return 1
    fi

    if [ ${ver[0]} -gt ${GO_MAJOR} ]; then
        echo "Bad golang version ${whole} in ${file} (expected ${GO_VER} or less)"
        return 1
    fi
    if [ ${ver[1]} -gt ${GO_MINOR} ]; then
        echo "Bad golang version ${whole} in ${file} (expected ${GO_VER} or less)"
        return 1
    fi
    if [ ${ver[1]} -eq ${GO_MINOR} -a ${ver[2]} -gt ${GO_PATCH} ]; then
        echo "Bad golang version ${whole} in ${file} (expected ${GO_VER} or less)"
        return 1
    fi
    echo "Version ${whole} in ${file} is good"
    return 0
}

echo "Looking at golang version: ${GO_VER}"

for f in $(find . -name "*.mod"); do
    v=$(sed -En 's/^go (.*)$/\1/p' ${f})
    if [ -z ${v} ]; then
        echo "Skipping ${f}: no version found"
    else
        if ! check_version ${v} ${f}; then
            RETCODE=1
        fi
    fi
done

for f in $(find . -name "*.mod"); do
    old=$(git grep -ohP '^go .*$' "${BASE_REF}" -- "${f}")
    new=$(git grep -ohP '^go .*$' "${f}")
    if [ "${new}" != "${old}" ]; then
        echo "New version of golang found in ${f}: \"${new}\" vs \"${old}\""
        RETCODE=1
    else
        echo "No golang version change detected in ${f}"
    fi
done

exit ${RETCODE}
