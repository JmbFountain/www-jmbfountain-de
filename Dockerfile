FROM nginx:latest
COPY src/_site/ /usr/share/nginx/html/
RUN chmod -R 555 /usr/share/nginx/html


