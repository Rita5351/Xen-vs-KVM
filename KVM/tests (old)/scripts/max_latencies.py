from pathlib import Path


test_cases = ["NRT-NRT", "NRT-RT", "RT-NRT", "RT-RT"]

for case in test_cases:
    max_latency = 0
    for i in range(1, 31):
        filename = Path(f"~/Xen-vs-KVM/KVM/tests/{case}/results_{i}.log").expanduser()
        with open(filename, 'r') as f:
            for line in f.readlines():
                tokens = line.strip().split()
                if tokens[1] == 'Max':
                    max_latency = max(max_latency, int(tokens[3]))
                    break
    print(f'Max latency for {case}: {max_latency}')

