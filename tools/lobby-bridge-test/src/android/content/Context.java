package android.content;

public class Context {
    public static final String CONNECTIVITY_SERVICE = "connectivity";
    public void startActivity(Intent i) { System.out.println("[test] startActivity " + i); }
    // (LobbyBridge.noNetwork, 2026-11-11: the laptop has a network, so downloads go on as before)
    public Object getSystemService(String name) {
        return CONNECTIVITY_SERVICE.equals(name) ? new android.net.ConnectivityManager() : null;
    }
}
