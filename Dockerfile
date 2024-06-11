# Use an official Microsoft SQL Server image
FROM mcr.microsoft.com/dotnet/core/sdk:3.1 as builder

RUN apt-get update
RUN apt-get install curl gnupg software-properties-common python3 python3-pip -y
RUN curl https://packages.microsoft.com/keys/microsoft.asc > gpg_key.txt && apt-key add gpg_key.txt
RUN curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | tee /etc/apt/sources.list.d/msprod.list
RUN apt-get update
ENV ACCEPT_EULA=Y
RUN apt-get install mssql-tools unixodbc-dev -y
RUN echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc

# Create a directory for the backup script
RUN mkdir /backup

# Copy the backup script to the container
COPY backup.sh /backup/backup_script.sh

# Make the script executable
RUN chmod +x /backup/backup_script.sh

# Set the entry point to run the backup script
ENTRYPOINT ["/backup/backup_script.sh"]
