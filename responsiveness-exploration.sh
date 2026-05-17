#!/bin/bash
#set -ex
if [[ ${EUID} -ne 0 ]]; then
	echo "$0 is not running as root. Try using sudo."
	exit 2
fi

iperfReference () {
  # iperf (UDP mode; 1Gbit; ul/dl separat messen) test der als referenz dient
  # muss 1x pro environment laufen
  touch debugging.txt
  # for singled out testing:
  # ./setup-shaping.sh CREATE 100Mbit 40Mbit 5ms 5ms  
  
  ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
  
  echo "server netcat" >> debugging.txt 2>&1
  ip netns exec server-net nc -lv 5001 >> debugging.txt
  echo "client netcat" >> debugging.txt
  echo "client netcat"
  ip netns exec client-net nc 10.237.0.3 5001 >> debugging.txt
  
  ./setup-shaping.sh DELETE
}


# single dimensional iteration through test parameters
iterParameters () {
  # loop over the environments (environment-name, capacities and delay in both directions)
  while IFS= read -r line || [ -n "${line}" ]; do    
    read -r envname dl_capacity ul_capacity dl_delay_from_inet ul_delay_to_inet <<< "${line}" # read the environment parameters
    mkdir outputfiles/${envname}

    # loop over the test-parameters (parameter-name, minimum and maximum value and iteration steps)  
    while IFS= read -r line || [ -n "$line" ]; do
      read -r test_parameter p_min p_max steps <<< "$line" # read the test parameter values, min, max and steps
      i=$p_min
      mkdir outputfiles/${envname}/${test_parameter}
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
          # we do 100 iterations
          for j in {1..100}; do
            mkdir outputfiles/${envname}/${test_parameter}/${j}           
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            # start server and get pid for killing later
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
            
            # log the set test parameters into output
            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> output.txt
            echo "Testing network environment ${envname} ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms"
            echo "Testing test parameter ${test_parameter} ${i}"
            echo "Testing test parameter ${test_parameter} ${i}" >> output.txt
            echo "iteration ${j}"
            echo "iteration ${j}" >> output.txt

            # start client and log it into output
            ip netns exec client-net ./networkQuality \
              --url https://networkquality.example.com:4043/.well-known/nq \
              --insecure-skip-verify -relative-rpm -extended-stats --"rpm.${test_parameter}" ${i} >> output.txt
            printf "\n" >> output.txt
            # kill server and delete network
            kill "$server_pid" 2>/dev/null || true
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
        for j in {1..1}; do
          mkdir outputfiles/${envname}/${test_parameter}/${j}             
          ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
          # start server and get pid for killing later
          ip netns exec server-net ./networkqualityd -create-cert --listen-addr 10.237.0.3 \
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

          # log the set test parameters into output
          echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> output.txt
          echo "Testing network environment ${envname} ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms"
          echo "Testing default"
          echo "iteration ${j}"
		      echo "iteration ${j}" >> output.txt

          # start client and log it into output
          ip netns exec client-net ./networkQuality \
            --connect-to 10.237.0.3 \
            --insecure-skip-verify -extended-stats -relative-rpm  >> output.txt
          printf "\n" >> output.txt
          # kill server and delete network
          kill "$server_pid" 2>/dev/null || true
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
          #  we do 100 iterations
          for j in {1..100}; do
            mkdir outputfiles/${envname}/${test_parameter}/${j} 
            ./setup-shaping.sh CREATE ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms
            # start server and get pid for killing later
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

            # log the set test parameters into output
            echo "Testing network environment ${envname} ${dl_capacity} ${ul_capacity} ${dl_delay_from_inet} ${ul_delay_to_inet}" >> output.txt
            echo "Testing network environment ${envname} ${dl_capacity}Mbit ${ul_capacity}Mbit ${dl_delay_from_inet}ms ${ul_delay_to_inet}ms"
            echo "Testing test parameter ${test_parameter} ${i}"
            echo "Testing test parameter ${test_parameter} ${i}" >> output.txt
            echo "iteration ${j}"
            echo "iteration ${j}" >> output.txt
			      
            # start client and log it into output
            ip netns exec client-net ./networkQuality \
              --url https://networkquality.example.com:4043/.well-known/nq \
              --insecure-skip-verify -extended-stats -relative-rpm --"rpm.${test_parameter}" ${i} >> output.txt
            printf "\n" >> output.txt
            # kill server and delete network
            kill "$server_pid" 2>/dev/null || true
            ./setup-shaping.sh DELETE
          done    
          ((i+=steps))
        done 
      fi     
      printf "\n" >> output.txt
    done < rpmparameters/testparameters.txt
    printf "\n" >> output.txt
  done < rpmparameters/environments.txt
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

if [ ! -f "output.txt" ]; then
  touch output.txt
fi
cat /dev/null > output.txt
iterParameters
mv output.txt outputfiles/
python3 create_csv.py # this will create a csv file with the output.txt
