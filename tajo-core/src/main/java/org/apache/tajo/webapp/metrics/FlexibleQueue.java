package org.apache.tajo.webapp.metrics;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import java.io.Serializable;
import java.util.Queue;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;

public class FlexibleQueue<T> implements IFlexibleQueue<T>, Serializable {
  private static final Log LOG = LogFactory.getLog(FlexibleQueue.class);

  final private TimeUnit timeunit = TimeUnit.MILLISECONDS;

  private long interval;
  private long duration;

  protected int size;
  private Queue<T> queue;

  public FlexibleQueue(Long interval, Long duration){
    this.interval = interval;
    this.duration = duration;

    init();
  }

  private void init(){
    this.size = (int)Math.ceil(this.duration/this.interval);
    this.queue = new ArrayBlockingQueue<T>(this.size);
  }

  public void resize(Long duration){
    if(duration != null){
      this.duration = duration;
    }
    this.size = (int)Math.ceil(this.duration/this.interval);
    if(this.queue!=null){
      synchronized (this.queue){
        Queue<T> tq = new ArrayBlockingQueue<T>(this.queue.size());
        this.queue = new ArrayBlockingQueue<T>(this.size);
        this.queue.addAll(tq);
      }
    }
  }

  @Override
  public void offer(T value){
    if(this.queue.size() >= this.size){
      this.queue.remove();
    }
    this.queue.offer(value);
  }

  @Override
  public T poll(){
    return this.queue.poll();
  }

  @Override
  public T peek(){
    return this.queue.peek();
  }

  public void clear(){
    this.queue.clear();
  }

  @Override
  public Queue<T> getQueue(){
    return this.queue;
  }
}