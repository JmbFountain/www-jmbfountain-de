FROM nginx:latest
RUN apt-get update
RUN apt-get install ruby-full build-essential -y
RUN gem install jekyll bundler
COPY src /src
WORKDIR /src/
RUN jekyll clean
RUN jekyll build
RUN cp -r /src/_site/ /usr/share/nginx/html/
RUN chmod -R 555 /usr/share/nginx/html


