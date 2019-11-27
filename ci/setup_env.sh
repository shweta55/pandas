#!/bin/bash -e

# edit the locale file if needed
if [ -n "$LOCALE_OVERRIDE" ]; then
    echo "Adding locale to the first line of pandas/__init__.py"
    rm -f pandas/__init__.pyc
    SEDC="3iimport locale\nlocale.setlocale(locale.LC_ALL, '$LOCALE_OVERRIDE')\n"
    sed -i "$SEDC" pandas/__init__.py
    echo "[head -4 pandas/__init__.py]"
    head -4 pandas/__init__.py
    echo
    sudo locale-gen "$LOCALE_OVERRIDE"
fi

IS_SUDO=""

if [ `uname -m` = 'aarch64' ]; then
   MINICONDA_DIR="$HOME/archiconda3"
   IS_SUDO="sudo"
else
   MINICONDA_DIR="$HOME/miniconda3"
fi

if [ -d "$MINICONDA_DIR" ]; then
    echo
    echo "rm -rf "$MINICONDA_DIR""
    rm -rf "$MINICONDA_DIR"
fi

echo "Install Miniconda"
UNAME_OS=$(uname)
if [[ "$UNAME_OS" == 'Linux' ]]; then
    if [[ "$BITS32" == "yes" ]]; then
        CONDA_OS="Linux-x86"
    else
        CONDA_OS="Linux-x86_64"
    fi
elif [[ "$UNAME_OS" == 'Darwin' ]]; then
    CONDA_OS="MacOSX-x86_64"
else
  echo "OS $UNAME_OS not supported"
  exit 1
fi

if [ `uname -m` = 'aarch64' ]; then
   wget -q "https://github.com/Archiconda/build-tools/releases/download/0.2.3/Archiconda3-0.2.3-Linux-aarch64.sh" -O archiconda.sh
   chmod +x archiconda.sh
   $IS_SUDO apt-get install python-dev
   $IS_SUDO apt-get install python3-pip
   $IS_SUDO apt-get install libpython3.7-dev
   $IS_SUDO apt-get install xvfb
   echo "/usr/local/bin/: "
   sudo ls /usr/local/bin/
   export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib:/usr/local/lib:/usr/local/bin/python
   ./archiconda.sh -b
   echo "chmod MINICONDA_DIR"
   $IS_SUDO -H chmod -R 777 $MINICONDA_DIR
   $IS_SUDO cp $MINICONDA_DIR/bin/* /usr/bin/
   $IS_SUDO rm /usr/bin/lsb_release
else
   wget -q "https://repo.continuum.io/miniconda/Miniconda3-latest-$CONDA_OS.sh" -O miniconda.sh
   chmod +x miniconda.sh
   ./miniconda.sh -b
fi

export PATH=$MINICONDA_DIR/bin:$PATH

echo
echo "which conda"
which conda

echo
echo "update conda"
conda config --set ssl_verify false
conda config --set quiet true --set always_yes true --set changeps1 false
$IS_SUDO conda install pip  # create conda to create a historical artifact for pip & setuptools
$IS_SUDO conda update -n base conda

echo "conda info -a"
conda info -a

echo
echo "set the compiler cache to work"
if [ -z "$NOCACHE" ] && [ "${TRAVIS_OS_NAME}" == "linux" ]; then
    echo "Using ccache"
    export PATH=/usr/lib/ccache:/usr/lib64/ccache:$PATH
    GCC=$(which gcc)
    echo "gcc: $GCC"
    CCACHE=$(which ccache)
    echo "ccache: $CCACHE"
    export CC='ccache gcc'
elif [ -z "$NOCACHE" ] && [ "${TRAVIS_OS_NAME}" == "osx" ]; then
    echo "Install ccache"
    brew install ccache > /dev/null 2>&1
    echo "Using ccache"
    export PATH=/usr/local/opt/ccache/libexec:$PATH
    gcc=$(which gcc)
    echo "gcc: $gcc"
    CCACHE=$(which ccache)
    echo "ccache: $CCACHE"
else
    echo "Not using ccache"
fi

echo "source deactivate"
source deactivate

echo "conda list (root environment)"
conda list

# Clean up any left-over from a previous build
# (note workaround for https://github.com/conda/conda/issues/2679:
#  `conda env remove` issue)
conda remove --all -q -y -n pandas-dev

echo
if [ `uname -m` = 'aarch64' ]; then
    $IS_SUDO chmod -R 777 $MINICONDA_DIR
    $IS_SUDO conda install numpy
    $IS_SUDO conda install hypothesis
    $IS_SUDO conda install pytz
    $IS_SUDO conda install nomkl
    #$IS_SUDO conda install pyarrow
    $IS_SUDO conda install s3fs
    #$IS_SUDO conda install boto3
    $IS_SUDO conda install s3transfer
    $IS_SUDO conda install pyreadstat
    $IS_SUDO python3.7 -m pip install pytest-xvfb
    $IS_SUDO python3.7 -m pip install python-dateutil
    $IS_SUDO chmod -R 777 $MINICONDA_DIR
fi

echo "conda env create -q --file=${ENV_FILE}"
time $IS_SUDO conda env create -q --file="${ENV_FILE}"


if [[ "$BITS32" == "yes" ]]; then
    # activate 32-bit compiler
    export CONDA_BUILD=1
fi

echo "activate pandas-dev"
source activate pandas-dev

echo
echo "remove any installed pandas package"
echo "w/o removing anything else"
$IS_SUDO conda remove pandas -y --force || true
if [ `uname -m` = 'aarch64' ]; then
    $IS_SUDO python3.7 -m pip uninstall -y pandas || true
else
    pip uninstall -y pandas || true
fi    

echo
echo "remove postgres if has been installed with conda"
echo "we use the one from the CI"
$IS_SUDO conda remove postgresql -y --force || true

echo
echo "conda list pandas"
conda list pandas

# Make sure any error below is reported as such

echo "[Build extensions]"
python setup.py build_ext -q -i

# XXX: Some of our environments end up with old versions of pip (10.x)
# Adding a new enough version of pip to the requirements explodes the
# solve time. Just using pip to update itself.
# - py35_macos
# - py35_compat
# - py36_32bit
echo "[Updating pip]"
$IS_SUDO python3.7 -m pip install --no-deps -U pip wheel setuptools

echo "[Install pandas]"
if [ `uname -m` = 'aarch64' ]; then
    $IS_SUDO chmod -R 777 $MINICONDA_DIR
    $IS_SUDO python3.7 -m pip install --no-build-isolation -e .
else
    python -m pip install --no-build-isolation -e .
fi    



echo
echo "conda list"
conda list

# Install DB for Linux
if [ "${TRAVIS_OS_NAME}" == "linux" ]; then
  echo "installing dbs"
  if [ `uname -m` = 'aarch64' ]; then
    sudo systemctl start mysql
    #sudo service postgresql start
  else
    psql -c 'create database pandas_nosetest;' -U postgres
  fi
  mysql -e 'create database pandas_nosetest;'
else
   echo "not using dbs on non-linux Travis builds or Azure Pipelines"
fi

echo "done"
