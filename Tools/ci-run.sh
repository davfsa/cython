#!/usr/bin/bash

# Set up compilers
if [ "${OS_NAME##ubuntu*}" == "" ]; then
    echo "Installing requirements [apt]"
    sudo apt-add-repository -y "ppa:ubuntu-toolchain-r/test"
    sudo apt update -y -q
    sudo apt install -y -q ccache gdb gcc-8
    if [ -z "${BACKEND##*cpp*}" ]; then
        sudo apt install -y -q g++-8
    fi
    sudo /usr/sbin/update-ccache-symlinks
    echo "/usr/lib/ccache" >> $GITHUB_PATH # export ccache to path

    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 60 $(if [ -z "${BACKEND##*cpp*}" ]; then echo " --slave /usr/bin/g++ g++ /usr/bin/g++-8"; fi)

    export CC="gcc"
    if [ -z "${BACKEND##*cpp*}" ]; then
        sudo update-alternatives --set g++ /usr/bin/g++-8
        export CXX="g++"
    fi
fi
if [ "${OS_NAME##macos*}" == "" ]; then
    export CC="clang -Wno-deprecated-declarations"
    export CXX="clang++ -stdlib=libc++ -Wno-deprecated-declarations"
fi

# Set up miniconda
if [ "$STACKLESS" == "true" ]; then
    echo "Installing stackless python"
    #conda install --quiet --yes nomkl --file=test-requirements.txt --file=test-requirements-cpython.txt
    conda config --add channels stackless
    conda install --quiet --yes stackless || exit 1
fi

# Log versions in use
echo "===================="
echo "|VERSIONS INSTALLED|"
echo "===================="
python -c 'import sys; print("Python %s" % (sys.version,))'
if [ "$CC" ]; then
    which ${CC%% *}
    ${CC%% *} --version
fi
if [ "$CXX" ]; then
    which ${CXX%% *}
    ${CXX%% *} --version
fi
echo "===================="

# Install python requirements
echo "Installing requirements [python]"
python -m pip install -r test-requirements.txt || exit 1
if [ "${PYTHON_VERSION##pypy*}" -a "${PYTHON_VERSION##3.[4789]*}" ]; then
    python -m pip install -r test-requirements-cpython.txt || exit 1
fi

if [ "$TEST_CODE_STYLE" == "1" ]; then
    STYLE_ARGS="--no-unit --no-doctest --no-file --no-pyregr --no-examples";
else
    STYLE_ARGS="--no-code-style";

    if [ -z "${BACKEND##*cpp*}" ]; then
        python -m pip install pythran==0.9.7 || exit 1
    fi
    if [ "$BACKEND" != "cpp" -a -n "${PYTHON_VERSION##2*}" -a -n "${PYTHON_VERSION##pypy*}" -a -n "${PYTHON_VERSION##*3.4}" ];then
        python -m pip install mypy || exit 1
    fi
fi

# Run tests
if [ "$COVERAGE" != "1" ]; then
    export CFLAGS="-O2 -ggdb -Wall -Wextra $(python -c 'import sys; print("-fno-strict-aliasing" if sys.version_info[0] == 2 else "")')"
    python setup.py build_ext -i $(python -c 'import sys; print("-j5" if sys.version_info >= (3,5) else "")') || exit 1
fi

export CFLAGS="-O0 -ggdb -Wall -Wextra"
python runtests.py -vv $STYLE_ARGS -x Debugger --backends=$BACKEND $LIMITED_API $EXCLUDE $(if [ "$COVERAGE" == "1" ]; then echo " --coverage"; fi) $(if [ -z "$TEST_CODE_STYLE" ]; then echo " -j7 "; fi) || exit 1
