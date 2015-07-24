<%
  /*
  * Licensed to the Apache Software Foundation (ASF) under one
  * or more contributor license agreements. See the NOTICE file
  * distributed with this work for additional information
  * regarding copyright ownership. The ASF licenses this file
  * to you under the Apache License, Version 2.0 (the
  * "License"); you may not use this file except in compliance
  * with the License. You may obtain a copy of the License at
  *
  * http://www.apache.org/licenses/LICENSE-2.0
  *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.
  */
%>
<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8"%>
<%@ page import="org.apache.tajo.master.TajoMaster" %>
<%@ page import="org.apache.tajo.service.ServiceTracker" %>
<%@ page import="org.apache.tajo.webapp.StaticHttpServer" %>
<%@ page import="java.net.InetSocketAddress" %>
<%@ page import="org.apache.tajo.master.rm.Worker" %>
<%@ page import="java.util.Map" %>
<%@ page import="java.util.Set" %>
<%@ page import="java.util.TreeSet" %>
<%@ page import="org.apache.tajo.master.cluster.WorkerConnectionInfo" %>
<%
  TajoMaster master = (TajoMaster) StaticHttpServer.getInstance().getAttribute("tajo.info.server.object");
  String[] masterName = master.getMasterName().split(":");
  InetSocketAddress socketAddress = new InetSocketAddress(masterName[0], Integer.parseInt(masterName[1]));
  String masterLabel = socketAddress.getAddress().getHostName()+ ":" + socketAddress.getPort();
  ServiceTracker haService = master.getContext().getHAService();
  String activeLabel = "";
  if (haService != null) {
      if (haService.isActiveMaster()) {
      activeLabel = "<font color='#1e90ff'>(active)</font>";
    } else {
      activeLabel = "<font color='#1e90ff'>(backup)</font>";
    }
  }
  Map<Integer, Worker> workers = master.getContext().getResourceManager().getWorkers();
  Set<Worker> liveWorkers = new TreeSet<Worker>();
  String headWorkerHttp = null;
  for(Worker eachWorker: workers.values()) {
    if(headWorkerHttp==null){
      WorkerConnectionInfo connectionInfo = eachWorker.getConnectionInfo();
      headWorkerHttp = connectionInfo.getHost() + ":" + connectionInfo.getHttpInfoPort();
    }
    liveWorkers.add(eachWorker);
  }
%>
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<link rel="stylesheet" type = "text/css" href="/static/style.css" />
  <link rel="stylesheet" type="text/css" href="/static/nv.d3.min.css" />
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<title>Tajo</title>
<script src="/static/js/jquery.js" type="text/javascript"></script>
<script src="/static/js/d3.min.js" type="text/javascript" charset="utf-8"></script>
<script src="/static/js/nv.d3.min.js" type="text/javascript"></script>
<script src="/static/js/moment.js" type="text/javascript"></script>
<style>
  div.group {
  }
  div.group > div.chart {
    display:inline-block;
  }
  svg {
    display: block;
    height: 250px !important;
    width: 400px !important;
  }
</style>
<script type="text/javascript">
(function ($) {
  $.tajoMonitor = {
    TYPE: {
      VALUE: 1,
      PERCENT: 2,
      BYTE: 3
    },
    KEY_PREFIX: '<%=masterLabel%>',
    KEY_DELIM: '-',
    BUF_SIZE: 30,
    TICK_TIME: 1000 * 10,
    getKey: function(metric, preKey){
      if(preKey){
        return (preKey + this.KEY_DELIM + metric).toLowerCase();
      }
      return (this.KEY_PREFIX + this.KEY_DELIM + metric).toLowerCase();
    },
    getSeri: function(obj){
      return JSON.stringify(obj);
    },
    getDeseri: function(str){
      return JSON.parse(str);
    },
    offerLocalStorage: function(metric, json, preKey){
      var keyMetric = this.getKey(metric, preKey);
      if(!localStorage.getItem(keyMetric)){
        localStorage.setItem(keyMetric, this.getSeri(new Array()));
      }
      var arr = this.getDeseri(localStorage.getItem(keyMetric));
      if(arr.length>=this.BUF_SIZE){
        arr.shift();
      }
      arr.push(json);
      localStorage.setItem(keyMetric, this.getSeri(arr));
    },
    getLocalStorage: function(metric, preKey){
      var keyMetric = this.getKey(metric, preKey);
      return this.getDeseri(localStorage.getItem(keyMetric));
    },
    clearLocalStorage: function(metric, preKey){
      var keyMetric = this.getKey(metric, preKey);
      localStorage.setItem(keyMetric, this.getSeri(new Array()));
    },
    getAjaxMetaData : function(callback, hostInfo){
      var protocol = location.protocol;
      $.ajax({
        url: (hostInfo)?protocol+'//'+hostInfo+'/metrics':'./metrics',
        data: { action: 'getMetrics' },
        dataType:'json',
        success:function(data){
          callback(data);
        }
      });
    }
  };
  // Parsers
  $.tajoMonitor.parser = {
    parseSummaryExcutions: function(meta){
      var makeValue = function(k, v){
        return {x: k, y: v};
      };
      var makeChartData = function(_k){
        var result = new Array();
        for (i = 0; i < _k.length; i++) {
          var $v = $.tajoMonitor.getLocalStorage(_k[i]);
          var item = {key: k[i], values: $v};
          result.push(item);
        }
        return result;
      };
      if(meta.success){
        var k = ['Average Execution Time', 'Min. Execution Time', 'Max. Execution Time'];
        var timestamp = meta.timestamp;
        var v = [meta.summary.averageExecutionTime, meta.summary.minExecutionTime, meta.summary.maxExecutionTime];
        $.each(k, function(index, value) {
          $.tajoMonitor.offerLocalStorage(k[index], makeValue(timestamp, v[index]));
        });
        return makeChartData(k);
      } else {
        return null;
      }
    },
    parseLiveWorkers: function(meta){
      var makeValue = function(key, value){
        return {key: key, value: value};
      };
      var makeChartData = function(_k, _v){
        var result = new Array();
        for (i = 0; i < _k.length; i++) {
          result.push(makeValue(_k[i], _v[i]));
        }
        return result;
      };
      if(meta.success){
        var k = ['Live Workers', 'Dead Workers'];
        var v = [meta.gauge['tajomaster.resource.liveWorkers'].value, meta.gauge['tajomaster.resource.deadWorkers'].value];
        var timestamp = meta.timestamp;
        return makeChartData(k, v);
      } else {
        return null;
      }
    },
    parseSummaryRunnings: function(meta){
      var makeValue = function(k, v){
        return {x: k, y: v};
      };
      var makeChartData = function(_k){
        var result = new Array();
        for (i = 0; i < _k.length; i++) {
          var $v = $.tajoMonitor.getLocalStorage(_k[i]);
          var item = {key: k[i], values: $v};
          result.push(item);
        }
        return result;
      };
      if(meta.success){
        var k = ['Running Queries', 'Finished Queries'];
        var v = [meta.summary.runningQueries, meta.summary.finishedQueries];
        var timestamp = meta.timestamp;
        $.each(k, function(index, value) {
          $.tajoMonitor.offerLocalStorage(k[index], makeValue(timestamp, v[index]));
        });
        return makeChartData(k);
      } else {
        return null;
      }
    },
    parseUptime: function(meta){
      if(meta.success){
        return parseInt(meta.summary.uptime/1000);
      } else {
        return null;
      }
    },
    parseSharedUsed: function(meta, k, type, preKey){
      var makeValue = function(k, v){
        return {x: k, y: v};
      };
      var makeChartData = function(_k, _preKey){
        var result = new Array();
        for (i = 0; i < _k.length; i++) {
          var $v = $.tajoMonitor.getLocalStorage(_k[i], _preKey);
          var item = {key: k[i], values: $v};
          result.push(item);
        }
        return result;
      };
      if(meta.success){
        var v = [];
        for (i = 0; i < k.length; i++) {
          var _val = 0;
          if(type == $.tajoMonitor.TYPE.PERCENT){
            _val = parseInt(meta.gauge[k[i]].value * 100);
          } else {
            _val = meta.gauge[k[i]].value;
          }
          v.push(_val);
        }
        var timestamp = meta.timestamp;
        $.each(k, function(index, value) {
          $.tajoMonitor.offerLocalStorage(k[index], makeValue(timestamp, v[index]), preKey);
        });
        return makeChartData(k, preKey);
      } else {
        return null;
      }
    },
    parseSharedUsage: function(meta, k){
      var makeValue = function(key, value){
        return {key: key, y: value};
      };
      var makeChartData = function(_k, _v){
        var result = new Array();
        for (i = 0; i < _k.length; i++) {
          result.push(makeValue(_k[i], _v[i]));
        }
        return result;
      };
      if(meta.success){
        var v = parseInt(meta.gauge[k[0]].value*100);
        var idle = parseInt(100-v);
            v = [v, idle];
        var timestamp = meta.timestamp;
        return makeChartData(k, v);
      } else {
        return null;
      }
    }
  };
  //Charts
  $.tajoMonitor.chart = {
    chartSummaryExcutions : null,
    loadSummaryExcutions : function(selector, data){
      try{
        if(!$.tajoMonitor.chart.chartSummaryExcutions){
          nv.addGraph(function() {
            $.tajoMonitor.chart.chartSummaryExcutions = nv.models.stackedAreaChart()
              .useInteractiveGuideline(true)
              .x(function(d) { return d[0] })
              .y(function(d) { return d[1] })
              .duration(300)
              .showControls(false);
            $.tajoMonitor.chart.chartSummaryExcutions.xAxis.tickFormat(function(d) { return d3.time.format('%X')(new Date(d)) });
            $.tajoMonitor.chart.chartSummaryExcutions.yAxis.tickFormat(d3.format(',.0f'));
            d3.select(selector)
              .datum(data)
              .transition().duration(1000)
              .call($.tajoMonitor.chart.chartSummaryExcutions);
            nv.utils.windowResize($.tajoMonitor.chart.chartSummaryExcutions.update);
          });
        } else {
          d3.select(selector)
            .datum(data);
          $.tajoMonitor.chart.chartSummaryExcutions.update();
        }
        return $.tajoMonitor.chart.chartSummaryExcutions;
      } catch(e) {
        console.log('Oops sorry, something wrong with data');
        console.log(e.description);
      }
    },
    chartLiveWorkers: null,
    loadLiveWorkers: function(selector, data){
      try{
        if(!$.tajoMonitor.chart.chartLiveWorkers){
          nv.addGraph(function () {
            $.tajoMonitor.chart.chartLiveWorkers = nv.models.pieChart()
                .x(function (d) { return d.key })
                .y(function (d) { return d.value })
                .donut(true)
                .showLabels(true)
                .donutLabelsOutside(true)
                .labelType('key')
                .valueFormat(d3.format(',.0f'));
              d3.select(selector)
                .datum(data)
                .transition().duration(1200)
                .call($.tajoMonitor.chart.chartLiveWorkers);
          });
        } else {
          d3.select(selector)
            .datum(data);
          $.tajoMonitor.chart.chartLiveWorkers.update();
        }
        return $.tajoMonitor.chart.chartLiveWorkers;
      } catch(e) {
        console.log('Oops sorry, something wrong with data');
        console.log(e.description);
      }
    },
    chartUptime: null,
    loadUptime: function(selector, data){
      try{
        if($.tajoMonitor.chart.chartUptime){
          $.tajoMonitor.chart.chartUptime.clearInterval();
        }
        $.tajoMonitor.chart.chartUptime = new Moment(data, function(obj){
          $(selector).html(obj.toString());
        });
        $(selector).html($.tajoMonitor.chart.chartUptime.toString());
      } catch(e) {
        console.log('Oops sorry, something wrong with data');
        console.log(e.description);
      }
    },
    chartSharedLine: [],
    loadSharedLine: function(selector, data, type){
      try{
        if(!$.tajoMonitor.chart.chartSharedLine[selector]){
          nv.addGraph(function() {
            $.tajoMonitor.chart.chartSharedLine[selector] = nv.models.lineChart()
                  .margin({left: 100})
                  .useInteractiveGuideline(true)
                  .showLegend(true)
                  .showYAxis(true)
                  .showXAxis(true);
            $.tajoMonitor.chart.chartSharedLine[selector].xAxis
                .axisLabel('Time')
                .tickFormat(function(d) { return d3.time.format('%X')(new Date(d))});
            $.tajoMonitor.chart.chartSharedLine[selector].yAxis
                .tickFormat(d3.format(',.0f'));
            var typeStr = null;
            if(type){
              if(type==$.tajoMonitor.TYPE.PERCENT){
                typeStr = '%';
              } else if(type==$.tajoMonitor.TYPE.BYTE) {
                typeStr = 'bytes';
              }
            }
            if(typeStr){
              $.tajoMonitor.chart.chartSharedLine[selector].yAxis.axisLabel(typeStr);
            }
            d3.select(selector)
              .datum(data)
              .call($.tajoMonitor.chart.chartSharedLine[selector]);
            $.tajoMonitor.chart.chartSharedLine[selector].update();
          });
        } else {
          d3.select(selector)
            .datum(data)
            .call($.tajoMonitor.chart.chartSharedLine[selector]);
          $.tajoMonitor.chart.chartSharedLine[selector].update();
        }
        return $.tajoMonitor.chart.chartSharedLine[selector];
      } catch(e) {
        console.log('Oops sorry, something wrong with data');
        console.log(e.description);
      }
    },
    chartSharedUsage: [],
    loadSharedUsage: function(selector, data){
      try{
        if(!$.tajoMonitor.chart.chartSharedUsage[selector]){
          nv.addGraph(function () {
            var arcRadius1 = [
              { inner: 0.6, outer: 1 },
              { inner: 0.65, outer: 0.95 }
            ];
            $.tajoMonitor.chart.chartSharedUsage[selector] = nv.models.pieChart()
              .x(function (d) { return d.key })
              .y(function (d) { return d.y })
              .donut(true)
              .showLabels(false)
              .growOnHover(false)
              .arcsRadius(arcRadius1)
              .valueFormat(d3.format(',.0f'));
            $.tajoMonitor.chart.chartSharedUsage[selector].title("0%");
            d3.select(selector)
              .datum(data)
              .transition().duration(1200)
              .call($.tajoMonitor.chart.chartSharedUsage[selector]);
            $.tajoMonitor.chart.chartSharedUsage[selector].title(data[0].y + "%");
            $.tajoMonitor.chart.chartSharedUsage[selector].update();
          });
        } else {
          d3.select(selector)
            .datum(data);
          $.tajoMonitor.chart.chartSharedUsage[selector].title(data[0].y + "%");
          $.tajoMonitor.chart.chartSharedUsage[selector].update();
        }
        return $.tajoMonitor.chart.chartSharedUsage[selector];
      } catch(e) {
        console.log('Oops sorry, something wrong with data');
        console.log(e.description);
      }
    }
  }
})(jQuery);
</script>
<script type="text/javascript">
var workerInterval = null;
$(document).ready(function() {
  if(typeof(Storage)!=="undefined"){
    var getAjaxMetaData = function(){
      $.tajoMonitor.getAjaxMetaData(function(data){
        var chartData = [$.tajoMonitor.parser.parseSummaryExcutions(data),
                        $.tajoMonitor.parser.parseLiveWorkers(data),
                        $.tajoMonitor.parser.parseSummaryRunnings(data),
                        $.tajoMonitor.parser.parseUptime(data),
                        $.tajoMonitor.parser.parseSharedUsed(data, ['tajomaster-jvm.Heap.heap.max', 'tajomaster-jvm.Heap.heap.used']),
                        $.tajoMonitor.parser.parseSharedUsed(data, ['tajomaster-jvm.Heap.total.max', 'tajomaster-jvm.Heap.total.used']),
                        $.tajoMonitor.parser.parseSharedUsage(data, ['tajomaster-jvm.Heap.heap.usage', 'idle'])
        ];
        $.tajoMonitor.chart.loadSharedLine('#summaryQueries svg', chartData[0]);
        $.tajoMonitor.chart.loadLiveWorkers('#summaryLiveWorkers svg', chartData[1]);
        $.tajoMonitor.chart.loadSharedLine('#summaryRunningQueries svg', chartData[2]);
        $.tajoMonitor.chart.loadUptime('#uptime', chartData[3]);
        $.tajoMonitor.chart.loadSharedLine('#tajoMasterJvmHeapMax svg', chartData[4], $.tajoMonitor.TYPE.BYTE);
        $.tajoMonitor.chart.loadSharedLine('#tajoMasterJvmHeapUsed svg', chartData[5], $.tajoMonitor.TYPE.BYTE);
        $.tajoMonitor.chart.loadSharedUsage('#tajoMasterJvmHeapUsage svg', chartData[6]);
      })
    };
    var getWorkerAjaxMetaData = function(workerHostinfo){
      $.tajoMonitor.getAjaxMetaData(function(data){
        var chartData = [$.tajoMonitor.parser.parseSharedUsed(data, ['worker-jvm.Heap.heap.max', 'worker-jvm.Heap.heap.used'], $.tajoMonitor.TYPE.VALUE,  workerHostinfo),
                        $.tajoMonitor.parser.parseSharedUsed(data, ['worker-jvm.Heap.total.max', 'worker-jvm.Heap.total.used'], $.tajoMonitor.TYPE.VALUE, workerHostinfo),
                        $.tajoMonitor.parser.parseSharedUsed(data, ['worker-jvm.Heap.non-heap.max', 'worker-jvm.Heap.non-heap.used'], $.tajoMonitor.TYPE.VALUE, workerHostinfo),
                        $.tajoMonitor.parser.parseSharedUsage(data, ['worker-jvm.Heap.heap.usage', 'idle']),
                        $.tajoMonitor.parser.parseSharedUsage(data, ['worker-jvm.Heap.non-heap.usage', 'idle']),
                        $.tajoMonitor.parser.parseSharedUsed(data, ['worker.querymaster.runningQueries'], $.tajoMonitor.TYPE.VALUE, workerHostinfo),
                        $.tajoMonitor.parser.parseSharedUsed(data, ['worker.task.runningTasks'], $.tajoMonitor.TYPE.VALUE, workerHostinfo),
                        $.tajoMonitor.parser.parseSharedUsed(data, ['worker-jvm.Heap.pools.PS-Eden-Space.usage', 'worker-jvm.Heap.pools.PS-Old-Gen.usage',
                                                                    'worker-jvm.Heap.pools.PS-Perm-Gen.usage', 'worker-jvm.Heap.pools.PS-Survivor-Space.usage'], $.tajoMonitor.TYPE.PERCENT, workerHostinfo),
                        $.tajoMonitor.parser.parseSharedUsed(data, ['worker-jvm.Thread.blocked.count', 'worker-jvm.Thread.waiting.count'], $.tajoMonitor.TYPE.VALUE, workerHostinfo)
        ];
        $.tajoMonitor.chart.loadSharedLine('#tajoWorkerJvmHeapHeapUsed svg', chartData[0], $.tajoMonitor.TYPE.BYTE);
        $.tajoMonitor.chart.loadSharedLine('#tajoWorkerJvmHeapTotalUsed svg', chartData[1], $.tajoMonitor.TYPE.BYTE);
        $.tajoMonitor.chart.loadSharedLine('#tajoWorkerJvmHeapNonHeapUsed svg', chartData[2], $.tajoMonitor.TYPE.BYTE);
        $.tajoMonitor.chart.loadSharedUsage('#tajoWorkerJvmHeapHeapUsage svg', chartData[3]);
        $.tajoMonitor.chart.loadSharedUsage('#tajoWorkerJvmHeapNonHeapUsage svg', chartData[4]);
        $.tajoMonitor.chart.loadSharedLine('#tajoQueryMasterRunningQueries svg', chartData[5]);
        $.tajoMonitor.chart.loadSharedLine('#tajoTaskRunningTasks svg', chartData[6]);
        $.tajoMonitor.chart.loadSharedLine('#tajoWorkerJvmHeapPoolsPS svg', chartData[7], $.tajoMonitor.TYPE.PERCENT);
        $.tajoMonitor.chart.loadSharedLine('#tajoWorkerJvmThreadCount svg', chartData[8]);
      }, workerHostinfo);
    };
    $('#selectLiveWorker').change(function() {
      if(workerInterval!=null){
        clearInterval(workerInterval);
      }
      var workerHostinfo = $(this).val();
      getWorkerAjaxMetaData(workerHostinfo);
      workerInterval = setInterval(function(){getWorkerAjaxMetaData(workerHostinfo)}, $.tajoMonitor.TICK_TIME);
    });
    getAjaxMetaData();
    setInterval(getAjaxMetaData, $.tajoMonitor.TICK_TIME);
    getWorkerAjaxMetaData('<%=headWorkerHttp%>');
    workerInterval = setInterval(function(){getWorkerAjaxMetaData('<%=headWorkerHttp%>')}, $.tajoMonitor.TICK_TIME);
  } else {
    console.log('Sorry! No Web Storage support..');
    alert('Sorry! No Web Storage support..');
  }
});
</script>
</head>
<body>
<%@ include file="header.jsp"%>
<div class='contents'>
  <!-- Body -->
  <h2>Tajo Master: <%=masterLabel%> <%=activeLabel%></h2>
  <hr/>
  <div>
    <h3>Summary</h3>
    <div class="group">
      <div class="group_summary">Uptime : <span id="uptime"></span></div>
      <div class="chart" id="summaryLiveWorkers"><svg></svg></div>
      <div class="chart" id="summaryQueries"><svg></svg></div>
      <div class="chart" id="summaryRunningQueries"><svg></svg></div>
    </div>
  </div>
  <hr />
  <div>
    <h3>Master</h3>
    <div class="group">
      <div class="chart" id="tajoMasterJvmHeapMax"><svg></svg></div>
      <div class="chart" id="tajoMasterJvmHeapUsed"><svg></svg></div>
      <div class="chart" id="tajoMasterJvmHeapUsage"><svg></svg></div>
    </div>
  </div>
  <hr />
  <div>
    <h3>Live Workers</h3>
    <div>
      <select id="selectLiveWorker">
        <%
          if(liveWorkers.isEmpty()) {
        %>
        <option value="">No Live Workers</option>
        <%
        } else {
          int no = 1;
          for(Worker worker: liveWorkers) {
            WorkerConnectionInfo connectionInfo = worker.getConnectionInfo();
            String workerHttp = connectionInfo.getHost() + ":" + connectionInfo.getHttpInfoPort();
        %>
        <option value="<%=workerHttp%>"><%=workerHttp%></option>
        <%
            } //end fo for
          } //end of if
        %>
      </select>
    </div>
    <div class="group">
      <div class="chart" id="tajoWorkerJvmHeapHeapUsed"><svg></svg></div>
      <div class="chart" id="tajoWorkerJvmHeapTotalUsed"><svg></svg></div>
      <div class="chart" id="tajoWorkerJvmHeapNonHeapUsed"><svg></svg></div>
    </div>
    <div class="group">
      <div class="chart" id="tajoQueryMasterRunningQueries"><svg></svg></div>
      <div class="chart" id="tajoTaskRunningTasks"><svg></svg></div>
      <div class="chart" id="tajoWorkerJvmHeapPoolsPS"><svg></svg></div>
    </div>
    <div class="group">
      <div class="chart" id="tajoWorkerJvmHeapHeapUsage"><svg></svg></div>
      <div class="chart" id="tajoWorkerJvmHeapNonHeapUsage"><svg></svg></div>
      <div class="chart" id="tajoWorkerJvmThreadCount"><svg></svg></div>
    </div>
  </div>
  <hr />
</div>
</body>
</html>