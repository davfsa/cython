# Correctly alias python
if [ -z "${PYTHON_VERSION##pypy*}" ]; then
    PYTHON="$(which ${PYTHON_VERSION})"
else
    PYTHON="$(which python${PYTHON_VERSION})"
fi

# Set up compilers
if [ "${OS_NAME##ubuntu*}" == "" ]; then
    echo "Installing requirements [apt]"
    sudo apt-add-repository -y "ppa:ubuntu-toolchain-r/test"
    sudo apt update -y -q
    sudo apt install -y -q gdb
    sudo apt install -y -q gcc-8
    if [ -z "${BACKEND##*cpp*}" ]; then
        sudo apt install -y -q g++-8
    fi

    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 60 $(if [ -z "${BACKEND##*cpp*}" ]; then echo " --slave /usr/bin/g++ g++ /usr/bin/g++-8"; fi)
    sudo update-alternatives --set gcc /usr/bin/gcc-8

    export CC=gcc
    if [ -z "${BACKEND##*cpp*}" ]; then
        sudo update-alternatives --set g++ /usr/bin/g++-8
        export CXX=g++
    fi
fi

# Set up miniconda
if [ "${OS_NAME##macos*}" == "" -o "$STACKLESS" == "true" ]; then
    echo "Installing Miniconda"
    if [ "${OS_NAME##macos*}" == "" ]; then
        CONDA_PLATFORM=MacOSX
    else
        CONDA_PLATFORM=Linux
    fi

    wget -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda$PY-latest-${CONDA_PLATFORM}-x86_64.sh || exit 1
    bash miniconda.sh -b -p $HOME/miniconda && rm miniconda.sh || exit 1
    echo "PATH = $HOME/miniconda/bin" >> $GITHUB_PATH # export conda to path
    conda --version || exit 1
    #conda install --quiet --yes nomkl --file=test-requirements.txt --file=test-requirements-cpython.txt

    if [ "${OS_NAME##macos*}" == "" ]; then
        export CC="clang -Wno-deprecated-declarations"
        export CXX="clang++ -stdlib=libc++ -Wno-deprecated-declarations"
    fi

    if [ "$STACKLESS" == "true" ]; then
        echo "Installing stackless python"
        conda config --add channels stackless
        conda install --quiet --yes stackless
    fi
fi

# Install python requirements
echo "Installing requirements [python]"
$PYTHON -m pip install -r test-requirements.txt
if [ -z "${PYTHON_VERSION##pypy*}" -o -z "${PYTHON_VERSION##3.[4789]*}" ]; then
    $PYTHON -m pip install -r test-requirements-cpython.txt
fi
if [ -z "${BACKEND##*cpp*}" ]; then
    $PYTHON -m pip install pythran
fi
if [ "$BACKEND" != "cpp" -a -n "${PYTHON_VERSION##2*}" -a -n "${PYTHON_VERSION##pypy*}" -a -n "${PYTHON_VERSION##*3.4}" ];then
    $PYTHON -m pip install mypy
fi

# Log versions in use
echo "===================="
echo "|VERSIONS INSTALLED|"
echo "===================="
$PYTHON -c 'import sys; print("Python %s" % (sys.version,))'
if [ "$CC" ]; then
    which ${CC%% *}
    ${CC%% *} --version
fi
if [ "$CXX" ]; then
    which ${CXX%% *}
    ${CXX%% *} --version
fi
echo "===================="

# Run tests
if [ "$TEST_CODE_STYLE" == "1" ]; then
    STYLE_ARGS="--no-unit --no-doctest --no-file --no-pyregr --no-examples";
else
    STYLE_ARGS=--no-code-style;
fi

if [ "$COVERAGE" != "1" ]; then
    CFLAGS="-O2 -ggdb -Wall -Wextra $($PYTHON -c 'import sys; print("-fno-strict-aliasing" if sys.version_info[0] == 2 else "")')"
    $PYTHON setup.py build_ext -i $($PYTHON -c 'import sys; print("-j5" if sys.version_info >= (3,5) else "")')
fi

CFLAGS="-O0 -ggdb -Wall -Wextra"
$PYTHON runtests.py -vv $STYLE_ARGS -x Debugger --backends=$BACKEND $LIMITED_API $EXCLUDE $(if [ "$COVERAGE" == "1" ]; then echo " --coverage"; fi) $(if [ -n "$TEST_CODE_STYLE" ]; then echo " -j7 "; fi)
