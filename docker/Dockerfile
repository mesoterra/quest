# use node12 image
FROM node:12
# create the working directory
WORKDIR /opt/quest
# clone quest repo
RUN git clone https://github.com/rearc/quest.git ./
# install dependencies
RUN npm install --only=production
# set port to expose
EXPOSE 3000
# start application
CMD [ "npm", "start" ]
