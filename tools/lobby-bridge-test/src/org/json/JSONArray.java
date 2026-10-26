package org.json;

import java.util.ArrayList;
import java.util.List;

public class JSONArray {
    final List<Object> list = new ArrayList<>();
    public JSONArray put(Object v) { list.add(v); return this; }
    public int length() { return list.size(); }
    public Object opt(int i) { return list.get(i); }
    @Override public String toString() {
        StringBuilder sb = new StringBuilder("[");
        for (Object v : list) { if (sb.length() > 1) sb.append(','); sb.append(JSONObject.write(v)); }
        return sb.append(']').toString();
    }
}
