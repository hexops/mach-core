FROM mcr.microsoft.com/devcontainers/typescript-node:0-18
ADD . .

ENV VERSION=0.12.0-dev.389+61b70778b

# set a global .gitignore
RUN echo '.devcontainer' > /home/node/.gitignore 
RUN git config --global core.excludesfile /home/node/.gitignore

RUN bash ./install-zig.sh
ENV AGREE=true