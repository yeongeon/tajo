package org.apache.tajo.webapp.metrics;

import java.util.HashMap;

public class MetricPair<K, V> extends HashMap<K, V> {
  public MetricPair(K key, V value){
    super.put(key, value);
  }
}
