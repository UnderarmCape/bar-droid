package org.json;

import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;

/** Test stand-in for Android's org.json (the subset LobbyBridge uses). */
public class JSONObject {
    public static final Object NULL = new Object() { @Override public String toString() { return "null"; } };
    final Map<String, Object> map = new LinkedHashMap<>();

    public JSONObject() {}
    public JSONObject(String s) throws JSONException {
        Object v = new Parser(s).value();
        if (!(v instanceof JSONObject)) throw new JSONException("not an object");
        map.putAll(((JSONObject) v).map);
    }

    public JSONObject put(String k, Object v) throws JSONException { map.put(k, v); return this; }
    public JSONObject put(String k, int v) throws JSONException { map.put(k, v); return this; }
    public JSONObject put(String k, long v) throws JSONException { map.put(k, v); return this; }
    public JSONObject put(String k, boolean v) throws JSONException { map.put(k, v); return this; }
    public boolean has(String k) { return map.containsKey(k); }
    public Object opt(String k) { return map.get(k); }
    public String optString(String k) { Object v = map.get(k); return v == null || v == NULL ? "" : v.toString(); }
    public boolean optBoolean(String k) { Object v = map.get(k); return v instanceof Boolean ? (Boolean) v : "true".equals(v); }
    public JSONObject optJSONObject(String k) { Object v = map.get(k); return v instanceof JSONObject ? (JSONObject) v : null; }
    public JSONArray optJSONArray(String k) { Object v = map.get(k); return v instanceof JSONArray ? (JSONArray) v : null; }
    public Iterator<String> keys() { return map.keySet().iterator(); }

    @Override public String toString() {
        StringBuilder sb = new StringBuilder("{");
        for (Map.Entry<String, Object> e : map.entrySet()) {
            if (sb.length() > 1) sb.append(',');
            sb.append(quote(e.getKey())).append(':').append(write(e.getValue()));
        }
        return sb.append('}').toString();
    }

    static String write(Object v) {
        if (v == null || v == NULL) return "null";
        if (v instanceof String) return quote((String) v);
        return v.toString();
    }

    static String quote(String s) {
        StringBuilder sb = new StringBuilder("\"");
        for (char c : s.toCharArray()) {
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                case '/': sb.append("\\/"); break;   // as Android's org.json
                default:
                    if (c < 0x20) sb.append(String.format("\\u%04x", (int) c)); else sb.append(c);
            }
        }
        return sb.append('"').toString();
    }

    static final class Parser {
        final String s; int i;
        Parser(String s) { this.s = s; }
        void ws() { while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++; }
        Object value() throws JSONException {
            ws();
            if (i >= s.length()) throw new JSONException("end of input");
            char c = s.charAt(i);
            if (c == '{') {
                i++; JSONObject o = new JSONObject(); ws();
                if (s.charAt(i) == '}') { i++; return o; }
                for (;;) {
                    ws(); String k = (String) value(); ws();
                    if (s.charAt(i++) != ':') throw new JSONException("expected : at " + i);
                    o.map.put(k, value()); ws();
                    char d = s.charAt(i++);
                    if (d == '}') return o;
                    if (d != ',') throw new JSONException("expected , at " + i);
                }
            }
            if (c == '[') {
                i++; JSONArray a = new JSONArray(); ws();
                if (s.charAt(i) == ']') { i++; return a; }
                for (;;) {
                    a.list.add(value()); ws();
                    char d = s.charAt(i++);
                    if (d == ']') return a;
                    if (d != ',') throw new JSONException("expected , at " + i);
                }
            }
            if (c == '"') {
                i++; StringBuilder sb = new StringBuilder();
                for (;;) {
                    char d = s.charAt(i++);
                    if (d == '"') return sb.toString();
                    if (d == '\\') {
                        char e = s.charAt(i++);
                        switch (e) {
                            case 'n': sb.append('\n'); break;
                            case 't': sb.append('\t'); break;
                            case 'r': sb.append('\r'); break;
                            case 'b': sb.append('\b'); break;
                            case 'f': sb.append('\f'); break;
                            case 'u': sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16)); i += 4; break;
                            default: sb.append(e);
                        }
                    } else sb.append(d);
                }
            }
            int start = i;
            while (i < s.length() && ",}] \t\r\n".indexOf(s.charAt(i)) < 0) i++;
            String t = s.substring(start, i);
            if (t.equals("true")) return true;
            if (t.equals("false")) return false;
            if (t.equals("null")) return NULL;
            try { return t.contains(".") || t.contains("e") || t.contains("E") ? (Object) Double.parseDouble(t) : (Object) Long.parseLong(t); }
            catch (NumberFormatException e) { throw new JSONException("bad token " + t); }
        }
    }
}
