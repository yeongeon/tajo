package org.apache.tajo.webapp.metrics;

import com.codahale.metrics.*;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.hadoop.service.CompositeService;
import org.apache.tajo.master.TajoMaster;
import org.apache.tajo.util.metrics.TajoSystemMetrics;
import org.apache.tajo.util.metrics.reporter.TajoMetricsReporter;
import org.apache.tajo.worker.TajoWorker;

import java.io.IOException;
import java.io.Serializable;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Map;
import java.util.SortedMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public class ThreadableMetricsChunk<T extends CompositeService> extends TajoMetricsReporter implements Serializable {
  private static final Log LOG = LogFactory.getLog(ThreadableMetricsChunk.class);

  private T service;
  private long interval = 1000;
  private long duration = 5*60*1000;
  private TimeUnit timeunit = TimeUnit.MILLISECONDS;
  private long lasttime = Calendar.getInstance().getTimeInMillis();
  private ConcurrentMap<String, FlexibleQueue<Map<Long, Object>>> metricsMap = new ConcurrentHashMap<String, FlexibleQueue<Map<Long, Object>>>();

  protected AtomicBoolean stop = new AtomicBoolean(false);
  private Thread collectorThread;

  @Override
  public void report(SortedMap<String, Gauge> gauges,
                     SortedMap<String, Counter> counters,
                     SortedMap<String, Histogram> histograms,
                     SortedMap<String, Meter> meters,
                     SortedMap<String, com.codahale.metrics.Timer> timers) {

    SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
    final String dateTime = dateFormat.format(new Date());
    double rateFactor = TimeUnit.SECONDS.toSeconds(1);
    Long now = Calendar.getInstance().getTimeInMillis();

    if (!gauges.isEmpty()) {
      Map<String, Map<String, Gauge>> gaugeGroups = findMetricsItemGroup(gauges);

      for(Map.Entry<String, Map<String, Gauge>> eachGroup: gaugeGroups.entrySet()) {
        gaugeGroupToPairs(this.metricsMap, now, rateFactor, eachGroup.getKey(), eachGroup.getValue());
      }
    }

    if (!counters.isEmpty()) {
      Map<String, Map<String, Counter>> counterGroups = findMetricsItemGroup(counters);

      for(Map.Entry<String, Map<String, Counter>> eachGroup: counterGroups.entrySet()) {
        counterGroupToPairs(this.metricsMap, now, rateFactor, eachGroup.getKey(), eachGroup.getValue());

      }
    }

    if (!histograms.isEmpty()) {
      Map<String, Map<String, Histogram>> histogramGroups = findMetricsItemGroup(histograms);

      for(Map.Entry<String, Map<String, Histogram>> eachGroup: histogramGroups.entrySet()) {
        histogramGroupToPairs(this.metricsMap, now, rateFactor, eachGroup.getKey(), eachGroup.getValue());
      }
    }

    if (!meters.isEmpty()) {
      Map<String, Map<String, Meter>> meterGroups = findMetricsItemGroup(meters);

      for(Map.Entry<String, Map<String, Meter>> eachGroup: meterGroups.entrySet()) {
        meterGroupToPairs(this.metricsMap, now, rateFactor, eachGroup.getKey(), eachGroup.getValue());
      }
    }

    if (!timers.isEmpty()) {
      Map<String, Map<String, com.codahale.metrics.Timer>> timerGroups = findMetricsItemGroup(timers);

      for(Map.Entry<String, Map<String, com.codahale.metrics.Timer>> eachGroup: timerGroups.entrySet()) {
        timerGroupToPairs(this.metricsMap, now, rateFactor, eachGroup.getKey(), eachGroup.getValue());
      }
    }
  }

  private class Collector<E> implements Runnable {
    private final E obj;

    private Collector(E obj) {
      this.obj = obj;
    }

    @Override
    public void run() {
      while(!stop.get()){
        try {
          Thread.sleep(interval);

          Long now = Calendar.getInstance().getTimeInMillis();
          Map<String, com.codahale.metrics.Metric> map = null;
          TajoSystemMetrics systemMetrics = null;
          if(service instanceof TajoMaster){
            TajoMaster master = (TajoMaster)service;
            systemMetrics = master.getContext().getMetrics();
          } else if(service instanceof TajoWorker){
            TajoWorker worker = (TajoWorker)service;
            systemMetrics = worker.getWorkerContext().getMetrics();
          }
          MetricRegistry metricRegistry = systemMetrics.getRegistry();
          report(metricRegistry.getGauges(),
              metricRegistry.getCounters(),
              metricRegistry.getHistograms(),
              metricRegistry.getMeters(),
              metricRegistry.getTimers());
          lasttime = now;
        } catch (InterruptedException e) {
        }
      }
    }
  }

  public ThreadableMetricsChunk(T service){
    this(service, null);
  }

  public ThreadableMetricsChunk(T service, Long interval){
    this(service, interval, null);
  }

  public ThreadableMetricsChunk(T service, Long interval, Long duration){
    if(service != null) {
      this.service = service;
    }
    if(interval != null) {
      this.interval = interval;
    }
    if(duration != null){
      this.duration = duration;
    }
  }

  public void start(){
    Object obj = new Object();
    collectorThread = new Thread(new Collector<Object>(obj));
    stop.set(false);
    collectorThread.start();
  }

  public Map<String, FlexibleQueue<Map<Long, Object>>> getMetrics(){
    /*
    try {
      long size = InstrumentationAgent.sizeOf(this.metricsMap);
      LOG.info(size +" bytes."); // 359528 bytes
      LOG.info((size/1024) +" kbytes.");
    } catch (IllegalAccessException e) {
      e.printStackTrace();
    }
    */

    return this.metricsMap;
  }

  public void restart(Long interval) throws Exception {
    this.restart(interval, null);
  }

  public void restart(Long interval, Long duration) throws Exception {
    if(interval != null) {
      this.interval = interval;
    }
    if(duration != null){
      this.duration = duration;
    }
  }

  public long getLasttime(){
    return this.lasttime;
  }

  public void stop() throws IOException {
    stop.set(true);
    collectorThread.interrupt();
    try{
      collectorThread.join();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }

  private void offerItem(String key, MetricPair pair){
    FlexibleQueue<Map<Long, Object>> q;
    if(metricsMap.containsKey(key)){
      q = metricsMap.get(key);
    } else {
      q = new FlexibleQueue<Map<Long, Object>>(interval, duration);
      metricsMap.put(key, q);
    }
    if(pair!=null) {
      q.offer(pair);
    }
  }

  private void meterGroupToPairs(ConcurrentMap<String, FlexibleQueue<Map<Long, Object>>> metricsMap, Long now,
                                 double rateFactor, String groupName, Map<String, Meter> meters) {
    for(Map.Entry<String, Meter> eachMeter: meters.entrySet()) {
      StringBuilder sb = new StringBuilder();
      sb.append(groupName);
      if(!groupName.isEmpty()) {
        sb.append(".");
      }
      sb.append(eachMeter.getKey());
      String key = sb.toString();

      Meter meter = eachMeter.getValue();
      offerItem((new StringBuilder(key)).append(".count").toString(), new MetricPair(now, meter.getCount()));
      offerItem((new StringBuilder(key)).append(".mean").toString(), new MetricPair(now, String.format("%2.2f", convertRate(meter.getMeanRate(), rateFactor))));
      offerItem((new StringBuilder(key)).append(".1minute").toString(), new MetricPair(now, String.format("%2.2f", String.format("%2.2f", convertRate(meter.getOneMinuteRate(), rateFactor)))));
      offerItem((new StringBuilder(key)).append(".5minute").toString(), new MetricPair(now, String.format("%2.2f", String.format("%2.2f", convertRate(meter.getFiveMinuteRate(), rateFactor)))));
      offerItem((new StringBuilder(key)).append(".15minute").toString(), new MetricPair(now, String.format("%2.2f", String.format("%2.2f", convertRate(meter.getFifteenMinuteRate(), rateFactor)))));
    }

  }

  private void counterGroupToPairs(ConcurrentMap<String, FlexibleQueue<Map<Long, Object>>> metricsMap, Long now,
                                   double rateFactor, String groupName, Map<String, Counter> counters) {
    for(Map.Entry<String, Counter> eachCounter: counters.entrySet()) {
      StringBuilder sb = new StringBuilder();
      sb.append(groupName);
      if(!groupName.isEmpty()) {
        sb.append(".");
      }
      sb.append(eachCounter.getKey());
      String key = sb.toString();

      offerItem(key, new MetricPair(now, eachCounter.getValue().getCount()));
    }
  }

  private void gaugeGroupToPairs(ConcurrentMap<String, FlexibleQueue<Map<Long, Object>>> metricsMap, Long now,
                                 double rateFactor, String groupName, Map<String, Gauge> gauges) {
    for(Map.Entry<String, Gauge> eachGauge: gauges.entrySet()) {
      StringBuilder sb = new StringBuilder();
      sb.append(groupName);
      if(!groupName.isEmpty()) {
        sb.append(".");
      }
      sb.append(eachGauge.getKey());
      String key = sb.toString();

      offerItem(key, new MetricPair(now, eachGauge.getValue().getValue()));
    }
  }

  private void histogramGroupToPairs(ConcurrentMap<String, FlexibleQueue<Map<Long, Object>>> metricsMap, Long now,
                                     double rateFactor, String groupName, Map<String, Histogram> histograms) {
    for(Map.Entry<String, Histogram> eachHistogram: histograms.entrySet()) {
      StringBuilder sb = new StringBuilder();
      sb.append(groupName);
      if(!groupName.isEmpty()) {
        sb.append(".");
      }
      sb.append(eachHistogram.getKey());
      String key = sb.toString();

      Histogram histogram = eachHistogram.getValue();
      Snapshot snapshot = histogram.getSnapshot();

      offerItem((new StringBuilder(key)).append(".min").toString(), new MetricPair(now, snapshot.getMin()));
      offerItem((new StringBuilder(key)).append(".max").toString(), new MetricPair(now, snapshot.getMax()));
      offerItem((new StringBuilder(key)).append(".mean").toString(), new MetricPair(now, String.format("%2.2f", snapshot.getMean())));
      offerItem((new StringBuilder(key)).append(".stddev").toString(), new MetricPair(now, String.format("%2.2f", snapshot.getStdDev())));
      offerItem((new StringBuilder(key)).append(".median").toString(), new MetricPair(now, String.format("%2.2f", snapshot.getMedian())));
      offerItem((new StringBuilder(key)).append(".75%").toString(), new MetricPair(now, String.format("%2.2f", snapshot.get75thPercentile())));
      offerItem((new StringBuilder(key)).append(".95%").toString(), new MetricPair(now, String.format("%2.2f", snapshot.get95thPercentile())));
      offerItem((new StringBuilder(key)).append(".98%").toString(), new MetricPair(now, String.format("%2.2f", snapshot.get98thPercentile())));
      offerItem((new StringBuilder(key)).append(".99%").toString(), new MetricPair(now, String.format("%2.2f", snapshot.get99thPercentile())));
      offerItem((new StringBuilder(key)).append(".999%").toString(), new MetricPair(now, String.format("%2.2f", snapshot.get999thPercentile())));
    }
  }

  private void timerGroupToPairs(ConcurrentMap<String, FlexibleQueue<Map<Long, Object>>> metricsMap, Long now,
                                 double rateFactor, String groupName, Map<String, com.codahale.metrics.Timer> timers) {

    for(Map.Entry<String, com.codahale.metrics.Timer> eachTimer: timers.entrySet()) {
      StringBuilder sb = new StringBuilder();
      sb.append(groupName);
      if(!groupName.isEmpty()) {
        sb.append(".");
      }
      sb.append(eachTimer.getKey());
      String key = sb.toString();

      com.codahale.metrics.Timer timer = eachTimer.getValue();
      Snapshot snapshot = timer.getSnapshot();

      offerItem((new StringBuilder(key)).append("count").toString(), new MetricPair(now, timer.getCount()));
      offerItem((new StringBuilder(key)).append("meanrate").toString(), new MetricPair(now, String.format("%2.2f", convertRate(timer.getMeanRate(), rateFactor))));
      offerItem((new StringBuilder(key)).append("1minuterate").toString(), new MetricPair(now, String.format("%2.2f", convertRate(timer.getOneMinuteRate(), rateFactor))));
      offerItem((new StringBuilder(key)).append("5minuterate").toString(), new MetricPair(now, String.format("%2.2f", convertRate(timer.getFiveMinuteRate(), rateFactor))));
      offerItem((new StringBuilder(key)).append("15minuterate").toString(), new MetricPair(now, String.format("%2.2f", convertRate(timer.getFifteenMinuteRate(),rateFactor))));
      offerItem((new StringBuilder(key)).append("min").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.getMin(), rateFactor))));
      offerItem((new StringBuilder(key)).append("max").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.getMax(),rateFactor))));
      offerItem((new StringBuilder(key)).append("mean").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.getMean(), rateFactor))));
      offerItem((new StringBuilder(key)).append("stddev").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.getStdDev(),rateFactor))));
      offerItem((new StringBuilder(key)).append("median").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.getMedian(), rateFactor))));
      offerItem((new StringBuilder(key)).append("75%").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.get75thPercentile(), rateFactor))));
      offerItem((new StringBuilder(key)).append("95%").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.get95thPercentile(), rateFactor))));
      offerItem((new StringBuilder(key)).append("98%").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.get98thPercentile(), rateFactor))));
      offerItem((new StringBuilder(key)).append("99%").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.get99thPercentile(), rateFactor))));
      offerItem((new StringBuilder(key)).append("999%").toString(), new MetricPair(now, String.format("%2.2f", convertRate(snapshot.get999thPercentile(),rateFactor))));
    }

  }
}