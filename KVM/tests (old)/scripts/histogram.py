import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

nrt_nrt = Path(r"~/Desktop/Xen-vs-KVM/KVM/tests/NRT-NRT/results_30.log").expanduser()
nrt_rt = Path(r"~/Desktop/Xen-vs-KVM/KVM/tests/NRT-RT/results_30.log").expanduser()
rt_nrt = Path(r"~/Desktop/Xen-vs-KVM/KVM/tests/RT-NRT/results_30.log").expanduser()
rt_rt = Path(r"~/Desktop/Xen-vs-KVM/KVM/tests/RT-RT/results_30.log").expanduser()

data_nrt_nrt = np.genfromtxt(nrt_nrt, comments='#')
data_nrt_rt = np.genfromtxt(nrt_rt, comments='#')
data_rt_nrt = np.genfromtxt(rt_nrt, comments='#')
data_rt_rt = np.genfromtxt(rt_rt, comments='#')

latencies_nrt_nrt = data_nrt_nrt[:, 0]
frequencies_nrt_nrt = data_nrt_nrt[:, 1]
latencies_nrt_rt = data_nrt_rt[:, 0]
frequencies_nrt_rt = data_nrt_rt[:, 1]
latencies_rt_nrt = data_rt_nrt[:, 0]
frequencies_rt_nrt = data_rt_nrt[:, 1]
latencies_rt_rt = data_rt_rt[:, 0]
frequencies_rt_rt = data_rt_rt[:, 1]

cdf_nrt_nrt = np.cumsum(frequencies_nrt_nrt) / np.sum(frequencies_nrt_nrt)
cdf_nrt_rt = np.cumsum(frequencies_nrt_rt) / np.sum(frequencies_nrt_rt)
cdf_rt_nrt = np.cumsum(frequencies_rt_nrt) / np.sum(frequencies_rt_nrt)
cdf_rt_rt = np.cumsum(frequencies_rt_rt) / np.sum(frequencies_rt_rt)

plt.figure(figsize=(8, 5))
plt.plot(latencies_nrt_nrt, cdf_nrt_nrt, marker='o', linestyle='-', color='r')
plt.plot(latencies_nrt_rt, cdf_nrt_rt, marker='s', linestyle='-', color='g')
plt.plot(latencies_rt_nrt, cdf_rt_nrt, marker='^', linestyle='-', color='m')
plt.plot(latencies_rt_rt, cdf_rt_rt, marker='*', linestyle='-', color='b')

plt.legend(['NRT-NRT', 'NRT-RT', 'RT-NRT', 'RT-RT'], loc='lower right')
plt.xlabel(r'Latenza ($\mu s$)')
plt.ylabel('Cumulative Distribution Function (CDF)')
plt.title('CDF of latency')
plt.grid(True, linestyle='--', alpha=0.7)

plt.xlim(left=0, right=max(latencies_rt_rt))
plt.ylim(0, 1.05)

plt.show()

# np.savetxt(
#     "cdf_data.txt",
#     np.column_stack((latencies_rt_rt, cdf)),
#     fmt="%.0f %.6f",
#     header="latency cdf",
#     comments=""
# )

# print("Dati CDF esportati")
