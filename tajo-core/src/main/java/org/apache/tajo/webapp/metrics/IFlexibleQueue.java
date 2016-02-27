package org.apache.tajo.webapp.metrics;

import java.util.Queue;

public interface IFlexibleQueue<T> {
  void offer(T value);
  T poll();
  T peek();
  void clear();
  Queue<T> getQueue();
}