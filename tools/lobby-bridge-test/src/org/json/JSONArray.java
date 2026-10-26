package org.json;

import java.util.ArrayList;
import java.util.List;

public class JSONArray {
    final List<Object> list = new ArrayList<>();
    public JSONArray put(Object v) { list.add(v); return this; }
    public int length() { return list.size(); }
    public Object opt(int i) { return list.get(i); }
    public String optString(int i) { Object v = i < list.size() ? list.get(i) : null; return v == null || v == JSONObject.NULL ? "" : v.toString(); }
    public JSONObject optJSONObject(int i) { Object v = i < list.size() ? list.get(i) : null; return v instanceof JSONObject ? (JSONObject) v : null; }
    @Override public String toString() {
        StringBuilder sb = new StringBuilder("[");
        for (Object v : list) { if (sb.length() > 1) sb.append(','); sb.append(JSONObject.write(v)); }
        return sb.append(']').toString();
    }
}
