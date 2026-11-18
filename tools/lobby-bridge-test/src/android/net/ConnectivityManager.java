package android.net;

// (a stand-in: a network is always there on the laptop)
public class ConnectivityManager {
    public Network getActiveNetwork() { return new Network(); }
}
