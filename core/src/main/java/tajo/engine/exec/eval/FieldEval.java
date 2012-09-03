package tajo.engine.exec.eval;

import com.google.gson.Gson;
import com.google.gson.annotations.Expose;
import tajo.catalog.Column;
import tajo.catalog.Schema;
import tajo.catalog.SchemaUtil;
import tajo.catalog.proto.CatalogProtos.DataType;
import tajo.datum.Datum;
import tajo.engine.json.GsonCreator;
import tajo.storage.Tuple;

/**
 * @author Hyunsik Choi 
 */
public class FieldEval extends EvalNode implements Cloneable {
	@Expose private Column column;
	@Expose	private int fieldId = -1;
	
	public FieldEval(String columnName, DataType domain) {
		super(Type.FIELD);
		this.column = new Column(columnName, domain);
	}
	
	public FieldEval(Column column) {
	  super(Type.FIELD);
	  this.column = column;
	}

	@Override
	public void eval(EvalContext ctx, Schema schema, Tuple tuple) {
	  if (fieldId == -1) {
	    if(schema.contains(column.getQualifiedName())) {
	     fieldId = schema.getColumnId(column.getQualifiedName());
	    } else {
	      if(schema.getColumnNum() != 0) {
	        String schemaColQualName = schema.getColumn(0).getTableName() + 
	            "." +  column.getColumnName();
	        fieldId = schema.getColumnId(schemaColQualName);
	      } else {
	        fieldId = schema.getColumnId(column.getQualifiedName());
	      }
	    }
	  }
    FieldEvalContext fieldCtx = (FieldEvalContext) ctx;
	  fieldCtx.datum = tuple.get(fieldId);
	}

  @Override
  public Datum terminate(EvalContext ctx) {
    return ((FieldEvalContext)ctx).datum;
  }

  @Override
  public EvalContext newContext() {
    return new FieldEvalContext();
  }

  private static class FieldEvalContext implements EvalContext {
    private Datum datum;

    public FieldEvalContext() {
    }
  }

  @Override
	public DataType [] getValueType() {
		return SchemaUtil.newNoNameSchema(column.getDataType());
	}
	
  public Column getColumnRef() {
    return column;
  }
	
	public String getTableId() {	  
	  return column.getTableName();
	}
	
	public String getColumnName() {
	  return column.getColumnName();
	}
	
	public void replaceColumnRef(String columnName) {
	  this.column.setName(columnName);
	}

	@Override
	public String getName() {
		return this.column.getQualifiedName();
	}
	
	public String toString() {
	  return this.column.toString();
	}
	
  public boolean equals(Object obj) {
    if (obj instanceof FieldEval) {
      FieldEval other = (FieldEval) obj;
      
      return column.equals(other.column);      
    }
    return false;
  }
  
  @Override
  public int hashCode() {
    return column.hashCode();
  }
  
  @Override
  public Object clone() throws CloneNotSupportedException {
    FieldEval eval = (FieldEval) super.clone();
    eval.column = (Column) this.column.clone();
    eval.fieldId = fieldId;
    
    return eval;
  }
  
  public String toJSON() {
    Gson gson = GsonCreator.getInstance();
    return gson.toJson(this, EvalNode.class);
  }

  public void preOrder(EvalNodeVisitor visitor) {
    visitor.visit(this);
  }
  
  @Override
  public void postOrder(EvalNodeVisitor visitor) {
    visitor.visit(this);
  }
}