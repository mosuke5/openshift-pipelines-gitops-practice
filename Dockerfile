FROM redhat/ubi8:8.7
RUN rpm -ivh https://dev.mysql.com/get/mysql80-community-release-el8-4.noarch.rpm
RUN dnf install -y python39 python3-devel mysql
RUN mkdir /app
WORKDIR /app
ADD requirements.txt /app/
RUN pip3 install -r requirements.txt
ADD . /app/
CMD ["flask", "run"]
