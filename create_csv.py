import csv
import operator as op
import os

# index        0
fieldnames = ['exp_parameters']
# index                    1              2              3           4
environment_parameters = ['dl_capacity', 'ul_capacity', 'dl_delay', 'ul_delay']
# index            5     6      7      8      9    10     11     12         13
rpm_parameters = ['id', 'mad', 'mnp', 'mps', 'p', 'ptc', 'sdt', 'timeout', 'tmp']

# index            14                       15                          16               17                18           19
dl_test_output = ['dl_stable_throughput',  'dl_stable_responsiveness', 'dl_throughput', 'dl_connections', 'dl_rpm_p', 'dl_rpm_trimmed']
# index            20                       21                          22               23                24          25
ul_test_output = ['ul_stable_throughput',  'ul_stable_responsiveness', 'ul_throughput', 'ul_connections', 'ul_rpm_p', 'ul_rpm_trimmed']
# index               26              27
final_test_output = ['final_rpm_p', 'final_rpm_trimmed']
# index                  28               29                     30            31                  32             33
relative_test_output = ['ub_base_rpm_p', 'ub_base_rpm_trimmed', 'base_rpm_p', 'base_rpm_trimmed', 'wc_effect_p', 'wc_effect_trimmed']

fieldnames = fieldnames + environment_parameters + rpm_parameters + dl_test_output + ul_test_output + final_test_output + relative_test_output

datalist = []


outputfile = os.path.join(os.getcwd(), "outputfiles/output.txt")
csvfile = os.path.join(os.getcwd(), "outputfiles/output.csv")

def initData(data):
    for i in range(0, 5):
        data[fieldnames[i]] = ''
    data[fieldnames[5]] = '1'
    data[fieldnames[6]] = '4'
    data[fieldnames[7]] = '16'
    data[fieldnames[8]] = '100'
    data[fieldnames[9]] = '90'
    data[fieldnames[10]] = '.05'
    data[fieldnames[11]] = '5'
    data[fieldnames[12]] = '20'
    data[fieldnames[13]] = '5'
    data[fieldnames[14]] = 'True'
    data[fieldnames[15]] = 'True'
    data[fieldnames[20]] = 'True'
    data[fieldnames[21]] = 'True'


def parseFile (filename):
    with open(filename, "r") as file:
        lines = file.readlines()
        data = {}
        initData(data)
        download = True
        for line in lines:
            line = line.strip()
            split_line = line.split()            
            if line.startswith("Testing"):                
                if op.contains(line, "environment"):
                    for i in range(0, 5):
                        data[fieldnames[i]] = split_line[i + 3]
                else:
                    data[fieldnames[0]] += ' ' + split_line[3]
                    data[split_line[3]] = split_line[4]
            elif line.startswith("Unbounded"):
                if op.contains(line, "Trimmed"):
                    data[fieldnames[29]] = split_line[3]
                else:
                    data[fieldnames[28]] = split_line[3]
            elif line.startswith("Baseline"):
                if op.contains(line, "Trimmed"):
                    data[fieldnames[31]] = split_line[2]
                else:
                    data[fieldnames[30]] = split_line[2]
            elif line.startswith("Download"):
                download = True
            elif line.startswith("Upload"):
                download = False
            elif line.startswith("Note"):
                if op.contains(line, "responsiveness"):
                    if download:
                        data[fieldnames[15]] = 'False'
                    else:
                        data[fieldnames[21]] = 'False'
                if op.contains(line, "throughput"):
                    if download:
                        data[fieldnames[14]] = 'False'
                    else:
                        data[fieldnames[20]] = 'False'
            elif line.startswith("Throughput"):
                if download:
                    data[fieldnames[16]] = split_line[1]
                    data[fieldnames[17]] = split_line[6]
                else:
                    data[fieldnames[22]] = split_line[1]
                    data[fieldnames[23]] = split_line[6]
            elif line.startswith("RPM"):
                if not op.contains(line, "Trimmed"):
                    if download:
                        if op.contains(line, "Inf") or op.contains(line, "NaN"):
                            data[fieldnames[18]] = '0'
                        else:
                            data[fieldnames[18]] = split_line[1]
                    else:
                        if op.contains(line, "Inf") or op.contains(line, "NaN"):
                            data[fieldnames[24]] = '0'
                        else:
                            data[fieldnames[24]] = split_line[1]
                else:
                    if download:
                        if op.contains(line, "Inf") or op.contains(line, "NaN"):
                            data[fieldnames[19]] = '0'
                        else:
                            data[fieldnames[19]] = split_line[1]
                    else:
                        if op.contains(line, "Inf") or op.contains(line, "NaN"):
                            data[fieldnames[25]] = '0'
                        else:
                            data[fieldnames[25]] = split_line[1]
            elif line.startswith("Final") and not op.contains(line, "Trimmed"):
                if op.contains(line, "Inf") or op.contains(line, "NaN"):
                    data[fieldnames[26]] = '0'
                else:
                    data[fieldnames[26]] = split_line[2]
            elif line.startswith("Final") and op.contains(line, "Trimmed"):
                if op.contains(line, "Inf") or op.contains(line, "NaN"):
                    data[fieldnames[27]] = '0'
                else:
                    data[fieldnames[27]] = split_line[2]
            elif line.startswith("Working"):
                if op.contains(line, "Trimmed"):
                    data[fieldnames[33]] = split_line[5][:-1]
                    datalist.append(data)
                    data = {}
                    initData(data)
                else:
                    data[fieldnames[32]] = split_line[5][:-1]
            


parseFile(outputfile)


# write the datalist into the csv file
with open(csvfile, 'w') as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(datalist)

print('created csv')