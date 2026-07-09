#!/bin/bash
#set -ex
if [[ ${EUID} -ne 0 ]]; then
	echo "$0 is not running as root. Try using sudo."
	exit 2
fi

iperfReference () {
  # iperf (UDP mode; 1Gbit; ul/dl separat messen) test der als referenz dient
  # muss 1x pro environment laufen
  touch "${TEST_DIR}/iperf_server.log"
  touch "${TEST_DIR}/iperf_client.log"
  touch "${TEST_DIR}/iperf_traffic.pcap"
  # for singled out testing:
  ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms  
  
  # start capturing
  ip netns exec bottleneck-net tcpdump -s 100 -G 3600 -i br-client-inet -w "${TEST_DIR}/iperf_traffic.pcap" 2> /tmp/tcpdump.log &
  TCPDUMP_PID=$!

  ip netns exec server-net iperf3 -s -B 10.237.0.3 > "${TEST_DIR}/iperf_server.log" 2>&1 &
  SERVER_PID=$!

  sleep 0.5

  echo "client iperf3" >> "${TEST_DIR}/iperf_client.log"
  ip netns exec client-net iperf3 -c 10.237.0.3 -t 15 -u -b 1G >> "${TEST_DIR}/iperf_client.log" 2>&1
  echo "client iperf3 reverse" >> "${TEST_DIR}/iperf_client.log"
  ip netns exec client-net iperf3 -c 10.237.0.3 -R -t 15 -u -b 1G >> "${TEST_DIR}/iperf_client.log" 2>&1

  
  kill -SIGINT $SERVER_PID
  wait $SERVER_PID
  echo "iperf3 killed."
  kill -SIGINT $TCPDUMP_PID
  wait $TCPDUMP_PID
  echo "tcpdump killed."
  
  ./setup-shaping.sh DELETE
}


# TODO: run "openssl req -x509 -newkey rsa:2048 -keyout privkey.pem -out fullchain.pem -days 365 -nodes -subj "/CN=networkquality.example.com""
# and use these cert and key for the server
# single dimensional iteration through test parameters
iterParameters () {
  # first we make a directory for the whole measurement:
  MEASUREMENT_DIR="outputfiles/measurement_$(date +%d-%m-%Y_%H-%M-%S)"
  # if on the server:
  # MEASUREMENT_DIR="/data/rpm_measurements/measurement_$(date +%d-%m-%Y_%H-%M-%S)"
  mkdir "${MEASUREMENT_DIR}"
  touch "${MEASUREMENT_DIR}/progress.log"
  # loop over the environments (environment-name, capacities and delay in both directions)
  while IFS= read -r line || [ -n "${line}" ]; do    
    read -r envname dl_capacity ul_capacity dl_delay_from_inet ul_delay_to_inet <<< "${line}" # read the environment parameters
    mkdir "${MEASUREMENT_DIR}/${envname}"
    # loop over the test-parameters (parameter-name, minimum and maximum value and iteration steps)  
    while IFS= read -r line || [ -n "$line" ]; do
      read -r test_parameter p_min p_max steps <<< "$line" # read the test parameter values, min, max and steps
      i=$p_min
      TEST_DIR="${MEASUREMENT_DIR}/${envname}/${test_parameter}"
      mkdir "${TEST_DIR}"      
      # if parameter is a float
      if [[ "${test_parameter}" = "ptc" ]]; then        
        # loop over the currently tested parameter
        # 1. emulation start
        # 2. server start
        # 3. wait until server reachable
        # 4. client start
        # (4. Client's output gets logged)
        # 5. server and emulation shutdown
        while [ "$(bc <<< "$i <= $p_max")" == "1"  ]; do
          mkdir "${TEST_DIR}/At${i}"                    
          # we do 100 iterations
          for j in {1..100}; do
            echo "currently: ${envname}_${test_parameter}_at${i}_iteration${j}" > "${MEASUREMENT_DIR}/progress.log"
            mkdir "${TEST_DIR}/At${i}/${j}"
            TEST_FILE="${TEST_DIR}/At${i}/${j}/test_output.log"
            PCAP_FILE="${TEST_DIR}/At${i}/${j}/traffic.pcap"
            KEYS_FILE="${TEST_DIR}/At${i}/${j}/test_keys.keys"
            SERVER_FILE="${TEST_DIR}/At${i}/${j}/server_output.log"
            touch ${TEST_FILE}
            cat /dev/null > ${TEST_FILE}          
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            
            # start capturing packets
            ip netns exec bottleneck-net tcpdump -s 100 -i br-client-inet -w "${PCAP_FILE}" 2> /tmp/tcpdump.log  &
            TCPDUMP_PID=$!
            
            # start server and get pid for killing later
            ip netns exec server-net ./networkqualityd -create-cert --listen-addr 10.237.0.3 \
              >${SERVER_FILE} 2>&1 &
            SERVER_PID=$!
            
            # Wait until the server port is reachable
            ip netns exec client-net bash -c '
              for i in {1..300}; do
                timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
                sleep 0.02
              done
              echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
              exit 1
            ' || { kill "$SERVER_PID" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }
            
            # log the set test parameters into output
            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> ${TEST_FILE}
            echo "Testing test parameter ${test_parameter} ${i}" >> ${TEST_FILE}
            echo "iteration ${j}" >> ${TEST_FILE} 

            # start client and log it into output
            ip netns exec client-net ./networkQuality \
              --connect-to 10.237.0.3 \
              --insecure-skip-verify -relative-rpm -extended-stats --"rpm.${test_parameter}" ${i} >> ${TEST_FILE}

            # kill server and tcpdump and delete network
            kill "$SERVER_PID" 2>/dev/null || true
            wait "$SERVER_PID" 2>/dev/null || true
            kill "$TCPDUMP_PID" 2>/dev/null || true
            wait "$TCPDUMP_PID" 2>/dev/null || true
            ./setup-shaping.sh DELETE
            done
          i=$(echo "$i + $steps" | bc -l)    
        done
      elif [[ "${test_parameter}" = "default" ]]; then # default means we use default parameter values
        # if we do a default iteration
        # 1. emulation start
        # 2. server start
        # 3. wait until server reachable
        # 4. client start
        # (4. Client's output gets logged)
        # 5. server and emulation shutdown
        iperfReference
        #  we do 100 iterations
        for j in {1..100}; do
          echo "currently: ${envname}_${test_parameter}_iteration${j}" > "${MEASUREMENT_DIR}/progress.log" 
          mkdir "${TEST_DIR}/${j}"
          TEST_FILE="${TEST_DIR}/${j}/test_output.log"
          PCAP_FILE="${TEST_DIR}/${j}/traffic.pcap"
          KEYS_FILE="${TEST_DIR}/${j}/keys.log"
          SERVER_FILE="${TEST_DIR}/${j}/server_output.log"
          touch ${TEST_FILE}
          cat /dev/null > ${TEST_FILE}              
          ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
          
          # start capturing packets
          ip netns exec bottleneck-net tcpdump -s 100 -i br-client-inet -w "${PCAP_FILE}" 2> /tmp/tcpdump.log  &
          TCPDUMP_PID=$!
          
          # start server and get pid for killing later
          ip netns exec server-net ./networkqualityd --create-cert --listen-addr 10.237.0.3 \
            >${SERVER_FILE} 2>&1 &
          SERVER_PID=$!

          # Wait until the server port is reachable
          ip netns exec client-net bash -c '
            for i in {1..300}; do
              timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
              sleep 0.02
            done
            echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
            exit 1
          ' || { kill "$SERVER_PID" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }

          # log the set test parameters into output
          echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> ${TEST_FILE}
		      echo "iteration ${j}" >> ${TEST_FILE}
 
          # start client and log it into output
          ip netns exec client-net ./networkQuality \
            --connect-to 10.237.0.3 \
            -extended-stats -relative-rpm >> ${TEST_FILE}

          # kill server and tcpdump and delete network
          kill "$SERVER_PID" 2>/dev/null || true
          wait "$SERVER_PID" 2>/dev/null || true
          kill "$TCPDUMP_PID" 2>/dev/null || true
          wait "$TCPDUMP_PID" 2>/dev/null || true
          ./setup-shaping.sh DELETE

        done
      else
        # for integers
        # 1. emulation start
        # 2. server start
        # 3. wait until server reachable
        # 4. client start
        # (4. Client's output gets logged)
        # 5. server and emulation shutdown
        while (( i <= p_max )); do
          mkdir "${TEST_DIR}/At${i}"
          #  we do 100 iterations
          for j in {1..100}; do
            echo "currently: ${envname}_${test_parameter}_at${i}_iteration${j}" > "${MEASUREMENT_DIR}/progress.log" 
            mkdir "${TEST_DIR}/At${i}/${j}"
            TEST_FILE="${TEST_DIR}/At${i}/${j}/test_output.log"
            PCAP_FILE="${TEST_DIR}/At${i}/${j}/traffic.pcap"
            KEYS_FILE="${TEST_DIR}/At${i}/${j}/test_keys.keys"
            SERVER_FILE="${TEST_DIR}/At${i}/${j}/server_output.log"
            touch ${TEST_FILE}
            cat /dev/null > ${TEST_FILE}
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            
            # start capturing packets
            ip netns exec bottleneck-net tcpdump -s 100 -i br-client-inet -w "${PCAP_FILE}" 2> /tmp/tcpdump.log  &
            TCPDUMP_PID=$!
            
            # start server and get pid for killing later
            ip netns exec server-net ./networkqualityd -create-cert -debug --listen-addr 10.237.0.3 \
              >${SERVER_FILE}2>&1 &
            SERVER_PID=$!
            # Wait until the server port is reachable
            ip netns exec client-net bash -c '
              for i in {1..300}; do
                timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
                sleep 0.02
              done
              echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
              exit 1
            ' || { kill "$SERVER_PID" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }

            # log the set test parameters into output
            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> ${TEST_FILE}
            echo "Testing test parameter ${test_parameter} ${i}" >> ${TEST_FILE}
            echo "iteration ${j}" >> ${TEST_FILE}

            # start client and log it into output
            ip netns exec client-net ./networkQuality \
              --connect-to 10.237.0.3 \
              --insecure-skip-verify -extended-stats -debug -relative-rpm --"rpm.${test_parameter}" ${i} >> ${TEST_FILE}

            # kill server and delete network
            kill "$SERVER_PID" 2>/dev/null || true
            wait "$SERVER_PID" 2>/dev/null || true
            kill "$TCPDUMP_PID" 2>/dev/null || true
            wait "$TCPDUMP_PID" 2>/dev/null || true
            ./setup-shaping.sh DELETE
          done    
          ((i+=steps))
        done 
      fi 
    done < rpmparameters/testparameters.txt
  done < rpmparameters/environments.txt
  echo "test done" > "${MEASUREMENT_DIR}/progress.log"
}

# iterate through a pair of test parameters
iterParametersTwoDims () {
  # loop over the environments (environment-name, capacities and delay in both directions)
  while IFS= read -r line || [ -n "${line}" ]; do    
    read -r envname dl_capacity ul_capacity dl_delay_from_inet ul_delay_to_inet <<< "${line}"  
    # This loop goes over the test parameter pairs defined in testparameters2.txt
    while IFS= read -r line || [ -n "$line" ]; do
      read -r test_parameter0 test_parameter1 <<< "$line"

      # in this loop we get the predefined range of values for each test parameter
      while IFS= read -r line || [ -n "$line" ]; do
        read -r parameter_name min max step <<< "${line}"
        if [["$parameter_name" == "$test_parameter0"]]; then
          i=min
          max0=max
          step0=step
        elif [ "$first_word" = "$target2" ]; then
          j=min
          max0=max
          step0=step
        fi
      done < rpmparameters/testparameters.txt
      
      # now we do 2 loops; each over a testparameter
      while [ $i -le $max0]; do
        while [ $j -le $max1]; do
          parameters=(--rpm.${test_parameter0} ${i} --rpm.${test_parameter1} ${j}) # parameter string that we append behind the client command
          # we do 100 iterations
          for k in {1..100}; do
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            # start server and save pid for killing later
            ip netns exec server-net ./networkqualityd -create-cert --public-name networkquality.example.com --listen-addr 10.237.0.3 \
              >server.log 2>&1 &
            server_pid=$!
            # Wait until the server port is reachable
            ip netns exec client-net bash -c '
              for i in {1..300}; do
                timeout 0.2 bash -c "</dev/tcp/10.237.0.3/4043" >/dev/null 2>&1 && exit 0
                sleep 0.02
              done
              echo "Timed out waiting for 10.237.0.3:4043 from client-net" >&2
              exit 1
            ' || { kill "$server_pid" 2>/dev/null || true; ./setup-shaping.sh DELETE; exit 1; }

            # log the parameters into output.txt
            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> output.txt
            echo "Testing network environment ${envname} ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms"
            echo "Testing test parameter ${test_parameter0} ${i}"
            echo "Testing test parameter ${test_parameter0} ${i}" >> output.txt
            echo "Testing test parameter ${test_parameter1} ${j}"
            echo "Testing test parameter ${test_parameter1} ${j}" >> output.txt
            echo "iteration ${k}"
            echo "iteration ${k}" >> output.txt
			
            # start client with the parameters
            ip netns exec client-net ./networkQuality \
              --url https://networkquality.example.com:4043/.well-known/nq \
              --insecure-skip-verify -extended-stats -relative-rpm "${parameters[@]}" >> output.txt
            printf "\n" >> output.txt
            # kill server and delete network
            kill "$server_pid" 2>/dev/null || true
            ./setup-shaping.sh DELETE
          done 
          ((j+=step1))
        done
        ((i+=step0))
      done
    done < rpmparameters/testparameters2.txt
    printf "\n" >> output.txt
  done < rpmparameters/environments.txt
}



iterParameters
# touch "${MEASUREMENT_DIR}/output.csv"
# python3 create_csv.py "${MEASUREMENT_DIR}" # this will create a csv file with the output.txt
