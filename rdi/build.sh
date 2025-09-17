# Download RDI
export RDI_VERSION=1.14.0

# check file already exists
mkdir -p "/content"
if [ ! -f "/content/rdi-installation-$RDI_VERSION.tar.gz" ]; then
    curl --output /content/rdi-installation-$RDI_VERSION.tar.gz -O https://redis-enterprise-software-downloads.s3.amazonaws.com/redis-di/rdi-installation-$RDI_VERSION.tar.gz
else
    echo "File rdi-installation-$RDI_VERSION.tar.gz already exists."
fi
