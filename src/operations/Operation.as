package operations
{
	import flash.events.EventDispatcher;
	
	/**
	 * Dispatched when the execution of an operation has been canceled.
	 */
	[Event(name="canceled", type="operations.OperationEvent")]
	
	/**
	 * Dispatched when the execution of an operation has started
	 */
	[Event(name="executed", type="operations.OperationEvent")]
	
	/**
	 * Dispatched when either an error or fault has occurred during the execution
	 * of an operation.
	 */
	[Event(name="fault", type="operations.FaultOperationEvent")]
	
	/**
	 * Dispatched when the execution of an operation has finished. Clients can check
	 * if an operation finished successfully by accessing the events 
	 * <code>successful</code> property.
	 */
	[Event(name="finished", type="operations.FinishedOperationEvent")]
	
	/**
	 * Dispatched a result was received during the execution of an operation. This event
	 * contains the parsed result data.
	 */
	[Event(name="result", type="operations.ResultOperationEvent")]
	
	/**
	 * The <code>Operation</code> is a base class representing an arbitrary atomic request.
	 * Requests can include a simple function call to a class, or more complex operations
	 * that require a network call.
	 * 
	 * @author Dan Schultz
	 */
	public class Operation extends EventDispatcher
	{
		/**
		 * Constructor.
		 */
		public function Operation()
		{
			super();
		}
		
		/**
		 * Cancels the request, if it can be canceled.
		 */
		final public function cancel():void
		{
			if (isExecuting) {
				_isExecuting = false;
				cancelRequest();
				fireCanceled();
				finish(false);
			}
		}
		
		/**
		 * Performs the actual cancelling of the request. This method is intended
		 * to be overridden by sub-classes and should not be called directly.
		 */
		protected function cancelRequest():void
		{
			
		}
		
		/**
		 * Executes the request.
		 */
		final public function execute():void
		{
			if (!isExecuting) {
				_isExecuting = true;
				fireExecuted();
				executeRequest();
			}
		}
		
		/**
		 * Performs the execution for this type of request. This method is intended
		 * to be overridden by sub-classes and should not be called directly.
		 */
		protected function executeRequest():void
		{
			
		}
		
		/**
		 * Called by sub-classes to indicate that an error or fault occurred during 
		 * the execution of the event. Calling this method will mark the operation
		 * as finished.
		 * 
		 * @param summary A simple description of the fault.
		 * @param detail A more detailed description of the fault.
		 */
		final protected function fault(summary:String, detail:String = ""):void
		{
			if (isExecuting) {
				fireFault(summary, detail);
				finish(false);
			}
		}
		
		/**
		 * Called by sub-classes to indicate that this operation is finished. This 
		 * method is automatically called when clients invoke either the <code>fault()</code>
		 * or <code>result()</code> methods, but may need to be invoked by sub-classes
		 * in specific cases which do not use these two methods. Do not call this method
		 * after invoking <code>result()</code> or <code>fault()</code>.
		 * 
		 * @param successful <code>true</code> if the operation is successful.
		 */
		final protected function finish(successful:Boolean):void
		{
			if (isExecuting) {
				_isExecuting = false;
				fireFinished(successful);
			}
		}
		
		private function fireCanceled():void
		{
			dispatchEvent( new OperationEvent(OperationEvent.CANCELED) );
		}
		
		private function fireExecuted():void
		{
			dispatchEvent( new OperationEvent(OperationEvent.CANCELED) );
		}
		
		private function fireFault(summary:String, detail:String = ""):void
		{
			dispatchEvent( new FaultOperationEvent(summary, detail) );
		}
		
		private function fireResult(data:Object):void
		{
			dispatchEvent( new ResultOperationEvent(data) );
		}
		
		private function fireFinished(successful:Boolean):void
		{
			dispatchEvent( new FinishedOperationEvent(successful) );
		}
		
		/**
		 * Called by a sub-class to indicate that a result was received during the 
		 * execution of the operation.
		 * 
		 * <p>
		 * When a result is received, sub-classes can choose to parse the data by 
		 * overriding the <code>parseResult()</code> method. If an error occurs
		 * during parsing, a fault is generated.
		 * <p>
		 * 
		 * <p>
		 * Calling this method will mark the operation as finished.
		 * </p>
		 * 
		 * @param data The unparsed result data.
		 */
		final protected function result(data:Object):void
		{
			if (isExecuting) {
				try {
					fireResult(parseResult(data));
					finish(true);
				} catch (e:Error) {
					fault(e.toString(), e.getStackTrace());
				}
			}
		}
		
		/**
		 * Called when result data is received during the execution of the operation.
		 * This method is called during the <code>result()</code> method, and allows
		 * sub-classes to parse and modify the original result data.
		 * 
		 * @param data The result data.
		 * @return The parsed result data.
		 */
		protected function parseResult(data:Object):Object
		{
			return data;
		}
		
		private var _isExecuting:Boolean;
		/**
		 * Indicates whether the request is currently executing.
		 */
		final public function get isExecuting():Boolean
		{
			return _isExecuting;
		}
	}
}