# A test configuration for debugging the boot loader.

config_interface: win32config
display_library: win32, options="traphotkeys, autoscale @GUI_DEBUG@"
cpu: model=p4_willamette, count=1, ips=50000000
cpu: reset_on_triple_fault=1, ignore_bad_msrs=1, msrs="msrs.def"
cpu: cpuid_limit_winnt=0
memory: guest=64, host=64
romimage: file=$BXSHARE/BIOS-bochs-latest, options=fastboot
vgaromimage: file=$BXSHARE/VGABIOS-lgpl-latest
mouse: enabled=0
pci: enabled=1, chipset=i440fx
private_colormap: enabled=0
log: bochsout.txt
panic: action=ask
error: action=report
info: action=report
debug: action=ignore, pci=report # report BX_DEBUG from module 'pci'
debugger_log: -
parport1: enabled=1, file="parport.out"
sound: driver=default, waveout=/dev/dsp. wavein=, midiout=
speaker: enabled=1, mode=sound, volume=15
port_e9_hack: enabled=1, all_rings=1
magic_break: enabled=1
ata0: enabled=1, ioaddr1=0x1f0, ioaddr2=0x3f0, irq=14
ata1: enabled=1, ioaddr1=0x170, ioaddr2=0x370, irq=15
ata2: enabled=0, ioaddr1=0x1e8, ioaddr2=0x3e0, irq=11
ata3: enabled=0, ioaddr1=0x168, ioaddr2=0x360, irq=9
boot: cdrom
floppy_bootsig_check: disabled=0
ata0-slave: type=cdrom, status=inserted, path=@IsoPath@
