class BoardMuseSNative extends BoardMuseS {

    private PacketLossTrackerGanglionSBLE packetLossTrackerGanglionNative;
    private String boardName;
    private int firmwareVersion = 0;

    public BoardMuseSNative() {
        super();
    }

    public BoardMuseSNative(String name, boolean showUpgradePopup) {
        super();
        this.boardName = name;

        if (name.indexOf("Muse S 1.3") != -1) {
            this.firmwareVersion = 3;
            output("Detected MuseS firmware version 3");
        }
        else {
            this.firmwareVersion = 2;
            output("Detected Muse S firmware version 2");
            if (showUpgradePopup) {
                PopupMessage msg = new PopupMessage("Warning", "MuseS firmware version 2 detected. Please update to version 3 for better performance. \n\nhttps://docs.openbci.com/MuseS/MuseSProgram");
            }
        }
    }

    @Override
    protected BrainFlowInputParams getParams() {
        BrainFlowInputParams params = new BrainFlowInputParams();
        params.serial_number = boardName;
        return params;
    }

    @Override
    public BoardIds getBoardId() {
        return BoardIds.MUSE_S_BOARD;
    }

    @Override
    public void setAccelerometerActive(boolean active) {
        super.setAccelerometerActive(active);

        if (packetLossTrackerGanglionNative != null) {
            // notify the packet loss tracker, because the sample indices change based
            // on whether accel is active or not
            packetLossTrackerGanglionNative.setAccelerometerActive(active);
        }
    }

    @Override
    protected PacketLossTracker setupPacketLossTracker() {
        if (firmwareVersion == 2) {
            packetLossTrackerGanglionNative = new PacketLossTrackerMGanglionBLE2(getSampleIndexChannel(), getTimestampChannel());
        }
        else if (firmwareVersion == 3) {
            packetLossTrackerGanglionNative = new PacketLossTrackerMGanglionBLE3(getSampleIndexChannel(), getTimestampChannel());
        }

        packetLossTrackerGanglionNative.setAccelerometerActive(isAccelerometerActive());
        return packetLossTrackerGanglionNative;
    }
};

abstract class BoardMuseS extends BoardBrainFlow implements AccelerometerCapableBoard {

    private final char[] deactivateChannelChars = {'1', '2', '3', '4', '5', '6', '7', '8', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i'};
    private final char[] activateChannelChars =  {'!', '@', '#', '$', '%', '^', '&', '*', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I'};
    
    private int[] accelChannelsCache = null;
    private int[] resistanceChannelsCache = null;

    private boolean[] exgChannelActive;

    protected String serialPort = "";
    protected String macAddress = "";
    protected String ipAddress = "";

    private boolean isCheckingImpedance = false;
    private boolean isGettingAccel = false;

    // implement mandatory abstract functions
    @Override
    protected BrainFlowInputParams getParams() {
        BrainFlowInputParams params = new BrainFlowInputParams();
        params.serial_port = serialPort;
        params.mac_address = macAddress;
        params.ip_address = ipAddress;
        params.ip_port = 6677;
        return params;
    }

    @Override
    public void setEXGChannelActive(int channelIndex, boolean active) {
        char[] charsToUse = active ? activateChannelChars : deactivateChannelChars;
        sendCommand(str(charsToUse[channelIndex]));
        exgChannelActive[channelIndex] = active;
    }
    
    @Override
    public boolean isEXGChannelActive(int channelIndex) {
        return exgChannelActive[channelIndex];
    }

    @Override
    public boolean initializeInternal()
    {
        // turn on accel by default, or is it handled somewhere else?
        boolean res = super.initializeInternal();
        
        setAccelerometerActive(true);
        exgChannelActive = new boolean[getNumEXGChannels()];
        Arrays.fill(exgChannelActive, true);

        return res;
    }

    @Override
    public boolean isAccelerometerActive() {
        return isGettingAccel;
    }

    @Override
    public void setAccelerometerActive(boolean active) {
        sendCommand(active ? "n" : "N");
        isGettingAccel = active;
    }

    @Override
    public boolean canDeactivateAccelerometer() {
        return true;
    }

    @Override
    public int[] getAccelerometerChannels() {
        if (accelChannelsCache == null) {
            try {
                accelChannelsCache = BoardShim.get_accel_channels(getBoardIdInt());
            } catch (BrainFlowError e) {
                e.printStackTrace();
            }
        }
        
        return accelChannelsCache;
    }

    public int[] getResistanceChannels() {
        if (resistanceChannelsCache == null) {
            try {
                resistanceChannelsCache = BoardShim.get_resistance_channels(getBoardIdInt());
            } catch (BrainFlowError e) {
                e.printStackTrace();
            }
        }

        return resistanceChannelsCache;
    }

    public void setCheckingImpedance(boolean checkImpedance) {
        if (checkImpedance) {
            if (isCheckingImpedance) {
                println("Already checking impedance.");
                return;
            }
            if (streaming) {
                stopRunning();
            }
            sendCommand("z");
            startStreaming();
            packetLossTracker = null;
        }
        else {
            if (!isCheckingImpedance) {
                println ("Impedance is not running.");
                return;
            }
            if (streaming) {
                stopStreaming();
            }
            sendCommand("Z");
            packetLossTracker = setupPacketLossTracker();
        }
        isCheckingImpedance = checkImpedance;
    }
    
    public boolean isCheckingImpedance() {
        return isCheckingImpedance;
    }
    
    @Override
    protected void addChannelNamesInternal(String[] channelNames) {
        for (int i=0; i<getAccelerometerChannels().length; i++) {
            channelNames[getAccelerometerChannels()[i]] = "Accel Channel " + i;
        }
    }

    @Override
    public List<double[]> getDataWithAccel(int maxSamples) {
        return getData(maxSamples);
    }

    @Override
    public int getAccelSampleRate() {
        return getSampleRate();
    }
};
