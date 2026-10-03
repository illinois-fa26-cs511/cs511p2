####################################################################################
# DO NOT MODIFY THE BELOW ##########################################################

FROM cs511p2-common

# DO NOT MODIFY THE ABOVE ##########################################################
####################################################################################

COPY ./setup-worker.sh ./setup-worker.sh
RUN /bin/bash setup-worker.sh

COPY ./start-worker.sh ./start-worker.sh
CMD ["/bin/bash", "start-worker.sh"]
