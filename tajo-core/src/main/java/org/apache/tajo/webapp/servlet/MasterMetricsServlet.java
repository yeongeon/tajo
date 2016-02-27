/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.tajo.webapp.servlet;

import com.codahale.metrics.Metric;
import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.tajo.master.TajoMaster;
import org.apache.tajo.webapp.StaticHttpServer;
import org.apache.tajo.webapp.metrics.FlexibleQueue;
import org.codehaus.jackson.map.DeserializationConfig;

import javax.servlet.ServletConfig;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Calendar;
import java.util.HashMap;
import java.util.Map;
import java.util.TreeMap;

public class MasterMetricsServlet extends AbstractExecutorServlet {
  private static final Log LOG = LogFactory.getLog(MasterMetricsServlet.class);
  private static final long serialVersionUID = -1517586415474706579L;

  private TajoMaster master;

  @Override
  public void init(ServletConfig config) throws ServletException {
    om.getDeserializationConfig().disable(
        DeserializationConfig.Feature.FAIL_ON_UNKNOWN_PROPERTIES);

    this.master = (TajoMaster) StaticHttpServer.getInstance().getAttribute("tajo.info.server.object");
  }

  @Override
  public void service(HttpServletRequest request,
                      HttpServletResponse response) throws ServletException, IOException {
    String action = request.getParameter("action");
    String type = request.getParameter("type");
    if(type!=null && type.equalsIgnoreCase("json")){
      type = "application/json";
    } else {
      type = "text/html";
    }
    Map<String, Object> returnValue = new HashMap<String, Object>();
    try {
      if(action == null || action.trim().isEmpty()) {
        errorResponse(response, "no action parameter.");
        return;
      }
      if("getMetrics".equals(action)) {
        if(this.master!=null){
          TreeMap<String, FlexibleQueue<Map<Long, Object>>> treeMap = new TreeMap<String, FlexibleQueue<Map<Long, Object>>>( this.master.getThreadableMetricsChunk().getMetrics());
          returnValue.put("metrics", treeMap);
        } else {
          returnValue.put("metrics", new TreeMap<String, Metric>());
        }
      }
      returnValue.put("success", "true");
      returnValue.put("timestamp", Calendar.getInstance().getTimeInMillis());
      writeHttpResponse(response, returnValue, type);
    } catch (Exception e) {
      LOG.error(e.getMessage(), e);
      errorResponse(response, e, type);
    }
  }
}
