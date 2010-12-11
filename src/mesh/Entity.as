package mesh
{
	import collections.ISet;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.IEventDispatcher;
	import flash.utils.Proxy;
	import flash.utils.flash_proxy;
	import flash.utils.setTimeout;
	
	import mesh.adaptors.ServiceAdaptor;
	import mesh.associations.AssociationCollection;
	import mesh.associations.AssociationProxy;
	import mesh.associations.BelongsToRelationship;
	import mesh.associations.HasManyRelationship;
	import mesh.associations.Relationship;
	import mesh.callbacks.AfterCallbackOperation;
	import mesh.callbacks.BeforeCallbackOperation;
	
	import mx.events.PropertyChangeEvent;
	
	import operations.EmptyOperation;
	import operations.FinishedOperationEvent;
	import operations.Operation;
	import operations.ParallelOperation;
	import operations.SequentialOperation;
	
	import reflection.clazz;
	import reflection.newInstance;
	
	import validations.Validator;
	
	/**
	 * An entity.
	 * 
	 * @author Dan Schultz
	 */
	public dynamic class Entity extends Proxy implements IEventDispatcher
	{
		private static const EXECUTION_DELAY:int = 50;
		
		private var _dispatcher:EventDispatcher;
		private var _callbacks:Array = [];
		
		/**
		 * Constructor.
		 */
		public function Entity()
		{
			super();
			
			_dispatcher = new EventDispatcher(this);
			_description = EntityDescription.describe(this);
			
			// add necessary callbacks
			beforeSave(isValid);
			beforeSave(populateForeignKeys);
			afterSave(SaveEntityRelationshipsOperation, _associations);
			
			addEventListener(PropertyChangeEvent.PROPERTY_CHANGE, handlePropertyChange);
		}
		
		private function addCallback(type:String, args:Array):void
		{
			var obj:Object = {};
			
			if (args[0] is Function) {
				if (type.indexOf("before") == 0) {
					obj.operationType = BeforeCallbackOperation;
				} else if (type.indexOf("after") == 0) {
					obj.operationType = AfterCallbackOperation;
				} else {
					throw new ArgumentError("Unsupported callback '" + type + "'");
				}
			} else if (args[0] is Class) {
				obj.operationType = args.shift();
			} else {
				throw new ArgumentError("Exepcted first argument to be a Function or Class.");
			}
			
			obj.type = type;
			obj.args = args;
			_callbacks.push(obj);
		}
		
		private function operationsForCallback(callback:String):Array
		{
			var filterFunc:Function = function(obj:Object, index:int, array:Array):Boolean
			{
				return obj.type == callback;
			};
			var mapFunc:Function = function(obj:Object, index:int, array:Array):Operation
			{
				return newInstance.apply(null, [obj.operationType].concat(obj.args));
			};
			
			return _callbacks.filter(filterFunc).map(mapFunc);
		}
		
		/**
		 * Checks if two entities are equal.  By default, two entities are equal
		 * when they are of the same type, and their ID's are the same.
		 * 
		 * @param entity The entity to check.
		 * @return <code>true</code> if the entities are equal.
		 */
		public function equals(entity:Entity):Boolean
		{
			return entity != null && 
				   ((isPersisted && id === entity.id) || this === entity) && 
				   clazz(this) == clazz(entity);
		}
		
		/**
		 * Removes the entity.
		 * 
		 * @param execute <code>false</code> if the operation should be returned without being
		 * 	executed.
		 * @return An executing operation.
		 */
		public function destroy(execute:Boolean = true):Operation
		{
			var beforeDestroy:SequentialOperation = new SequentialOperation(operationsForCallback("beforeDestroy"));
			var destroy:Operation = adaptorFor(this).destroy(this);
			var afterDestroy:SequentialOperation = new SequentialOperation(operationsForCallback("afterDestroy"));
			
			var operation:Operation = beforeDestroy.then(destroy).then(afterDestroy);
			operation.addEventListener(FinishedOperationEvent.FINISHED, function(event:FinishedOperationEvent):void
			{
				if (event.successful) {
					_isDestroyed = true;
				}
			});
			
			if (execute) {
				setTimeout(operation.execute, EXECUTION_DELAY);
			}
			
			return operation;
		}
		
		protected function beforeDestroy(... args):void
		{
			addCallback("beforeDestroy", args);
		}
		
		protected function afterDestroy(... args):void
		{
			addCallback("afterDestroy", args);
		}
		
		private function handlePropertyChange(event:PropertyChangeEvent):void
		{
			propertyChanged(event.property.toString(), event.oldValue, event.newValue);
		}
		
		/**
		 * Returns a generated hash value for this entity.  Two entities that represent
		 * the same data should return the same hash code.
		 * 
		 * @return A hash value.
		 */
		public function hashCode():Object
		{
			return id;
		}
		
		/**
		 * Runs the validations defined for this entity and returns <code>true</code> if any
		 * validations failed.
		 * 
		 * @return <code>true</code> if any validations failed.
		 * 
		 * @see #isValid()
		 * @see #validate()
		 */
		public function isInvalid():Boolean
		{
			return !isValid();
		}
		
		/**
		 * Runs the validations defined for this entity and returns <code>true</code> if all
		 * validations passed.
		 * 
		 * @return <code>true</code> if all validations passed.
		 * 
		 * @see #isInvalid()
		 * @see #validate()
		 */
		public function isValid():Boolean
		{
			return validate().length == 0;
		}
		
		private function populateForeignKeys():void
		{
			for each (var relationship:Relationship in _description.relationships) {
				if (relationship is BelongsToRelationship) {
					this[(relationship as BelongsToRelationship).foreignKey] = this[relationship.property].id;
				}
			}
		}
		
		/**
		 * Marks a property on the entity as being dirty. This method allows sub-classes to manually 
		 * manage when a property changes.
		 * 
		 * @param property The property that was changed.
		 * @param oldValue The property's old value.
		 * @param newValue The property's new value.
		 */
		protected function propertyChanged(property:String, oldValue:Object, newValue:Object):void
		{
			_properties.changed(property, oldValue, newValue);
		}
		
		/**
		 * Reverts all changes made to this entity since the last save.
		 */
		public function revert():void
		{
			_properties.revert();
			
			for each (var relationship:Relationship in _description.relationships) {
				if (hasOwnProperty(relationship.property) && this[relationship.property] != null) {
					this[relationship.property].revert();
				}
			}
		}
		
		/**
		 * Saves the entity by executing either a create or update operation on the entity's 
		 * service.
		 * 
		 * <p>
		 * By default, save will always run the entity's validations. Clients can bypass this
		 * functionality by passing <code>false</code>. If any validation fails, save will 
		 * return <code>false</code>. Otherwise, an executed <code>Operation</code> is returned.
		 * </p>
		 * 
		 * @param validate <code>false</code> if validations should be ignored.
		 * @param execute <code>false</code> if the operation should be returned without being
		 * 	executed.
		 * @return An executing operation, or <code>false</code> if a validation fails.
		 */
		public function save(validate:Boolean = true, execute:Boolean = true):Operation
		{
			var beforeSave:SequentialOperation = new SequentialOperation(operationsForCallback("beforeSave"));
			var save:Operation = hasPropertyChanges ? (isNew ? adaptorFor(this).create(this) : adaptorFor(this).update(this)) : new EmptyOperation();
			var afterSave:SequentialOperation = new SequentialOperation(operationsForCallback("afterSave"));
			
			var operation:Operation = beforeSave.then(save).then(afterSave);
			operation.addEventListener(FinishedOperationEvent.FINISHED, function(event:FinishedOperationEvent):void
			{
				if (event.successful) {
					saved();
				}
			});
			
			if (execute) {
				setTimeout(operation.execute, EXECUTION_DELAY);
			}
			
			return operation;
		}
		
		/**
		 * Adds a callback function that will be executed before a save operation. If this 
		 * function returns <code>false</code> or throws an error, the save will halt.
		 * 
		 * @param callback The callback function.
		 */
		protected function beforeSave(...args):void
		{
			addCallback("beforeSave", args);
		}
		
		/**
		 * Adds a callback function that will be executed after a save operation has finished.
		 * 
		 * @param callback
		 * 
		 */
		protected function afterSave(...args):void
		{
			addCallback("afterSave", args);
		}
		
		/**
		 * Marks this entity as being persisted.
		 */
		public function saved():void
		{
			_properties.clear();
		}
		
		/**
		 * Copies the translated values on the given object to this entity. This method is useful for
		 * copying the values of a transfer object or XML into the entity for service calls.
		 * 
		 * @param object The object to translate and copy.
		 */
		public function translateFrom(object:Object):void
		{
			
		}
		
		/**
		 * Creates a new translation object, which is useful for creating transfer objects or XML for
		 * service calls.
		 * 
		 * @return A new translation object.
		 */
		public function translateTo():Object
		{
			return null;
		}
		
		/**
		 * Returns the mapped instance of the service adaptor for the given entity.
		 * 
		 * @param entity The entity to get the service adaptor for.
		 * @return A service adaptor.
		 */
		public static function adaptorFor(entity:Object):ServiceAdaptor
		{
			return EntityDescription.describe(entity).adaptor;
		}
		
		/**
		 * Runs the validations defined on this entity and returns the set of errors for
		 * any validations that failed. If all validations passed, this method returns an
		 * empty array.
		 * 
		 * <p>
		 * Calling this method will also populate the <code>Entity.errors</code> property with
		 * the validation results.
		 * </p>
		 *
		 * @return A set of <code>ValidationError</code>s.
		 * 
		 * @see #isInvalid()
		 * @see #isValid()
		 * @see #errors
		 */
		public function validate():Array
		{
			var results:Array = [];
			for each (var validator:Validator in _description.validators) {
				results = results.concat(validator.validate(this));
			}
			_errors = results;
			return results;
		}
		
		private var _description:EntityDescription;
		/**
		 * The description that contains the aggregates, relationships, validators and service
		 * adaptor for this entity.
		 */
		public function get description():EntityDescription
		{
			return _description;
		}
		
		private var _errors:Array = [];
		/**
		 * A set of <code>ValidationResult</code>s that failed during the last call to 
		 * <code>validate()</code>.
		 * 
		 * @see #validate()
		 */
		public function get errors():Array
		{
			return _errors.concat();
		}
		
		private var _id:*;
		/**
		 * An object that represents the ID for this entity.
		 */
		public function get id():*
		{
			return _id;
		}
		public function set id(value:*):void
		{
			if (value == 0) {
				value = undefined;
			}
			if (value == "") {
				value = undefined;
			}
			if (value == null) {
				value = undefined;
			}
			_id = value;
		}
		
		private var _isDestroyed:Boolean;
		/**
		 * <code>true</code> if this record has been destroyed.
		 */
		public function get isDestroyed():Boolean
		{
			return _isDestroyed;
		}
		
		/**
		 * <code>true</code> if this entity is either a new record or contains any property changes.
		 * This does not check to see if its associations are dirty.
		 * 
		 * @see #isDirty
		 * @see #hasDirtyAssociations
		 */
		public function get hasPropertyChanges():Boolean
		{
			return isNew || _properties.hasChanges;
		}
		
		/**
		 * <code>true</code> if this entity contains any associations that are dirty.
		 * 
		 * @see #isDirty
		 * @see #hasPropertyChanges
		 */
		public function get hasDirtyAssociations():Boolean
		{
			// more in depth check on the entity's relationships.
			for each (var relationship:Relationship in _description.relationships) {
				if (!(relationship is BelongsToRelationship)) {
					var association:AssociationProxy = this[relationship.property];
					if (association != null && association.isDirty) {
						return true;
					}
				}
			}
			return false;
		}
		
		/**
		 * <code>true</code> if this entity is dirty and needs to be persisted. An object is dirty
		 * if any of its properties have changed since its last save or if its a new record. An
		 * entity is also dirty if any of its relationships are dirty.
		 */
		public function get isDirty():Boolean
		{
			return hasPropertyChanges || hasDirtyAssociations;
		}
		
		/**
		 * <code>true</code> if this entity is a new record that needs to be persisted. By default, 
		 * an entity is considered new if its ID is 0. Sub-classes may override this implementation
		 * and provide their own.
		 */
		public function get isNew():Boolean
		{
			return id === undefined;
		}
		
		/**
		 * <code>true</code> if the entity is persisted in the entity's service. An entity is persisted
		 * when it hasn't been destroyed and its not a new record.
		 */
		public function get isPersisted():Boolean
		{
			return !isNew && !isDestroyed;
		}
		
		/**
		 * A set of properties that are accessible on this entity. Properties include any that
		 * are defined on the entity and its sub-classes, and any properties defined within 
		 * metadata, such as <code>ComposedOf</code> or <code>HasOne</code>.
		 */
		public function get properties():ISet
		{
			return _description.properties;
		}
		
		private var _properties:Properties = new Properties(this);
		private var _associations:Properties = new Properties(this);
		/**
		 * @private
		 */
		override flash_proxy function getProperty(name:*):*
		{
			var relationship:Relationship = _description.getRelationshipForProperty(name);
			if (relationship != null) {
				if (!_associations.hasOwnProperty(relationship.property)) {
					_associations[relationship.property] = relationship.createProxy(this);
				}
			}
			
			if (_associations.hasOwnProperty(name)) {
				var association:AssociationProxy = _associations[name];
				if (association is AssociationCollection) {
					return association;
				}
				return association.target;
			}
			
			if (_properties.hasOwnProperty(name)) {
				return _properties[name];
			}
			
			var aggregate:Aggregate = _description.getAggregateForProperty(name);
			if (aggregate != null && aggregate.property != name.toString()) {
				return aggregate.getValue(this, name);
			}
			
			if (name.toString().lastIndexOf("Was") == name.toString().length-3) {
				var property:String = name.toString().substr(0, name.toString().length-3);
				
				aggregate = _description.getAggregateForProperty(property);
				if (aggregate != null) {
					var aggregateValue:Object = _properties.oldValueOf(aggregate.property);
					if (aggregateValue != null) {
						return aggregateValue[aggregate.getMappedProperty(property)];
					}
				}
				return _properties.oldValueOf(property);
			}
			
			return undefined;
		}
		
		/**
		 * @private
		 */
		override flash_proxy function hasProperty(name:*):Boolean
		{
			return flash_proxy::getProperty(name) !== undefined;
		}
		
		/**
		 * @private
		 */
		override flash_proxy function setProperty(name:*, value:*):void
		{
			var relationship:Relationship = _description.getRelationshipForProperty(name);
			if (relationship != null) {
				if (!_associations.hasOwnProperty(relationship.property)) {
					_associations[relationship.property] = relationship.createProxy(this);
				}
				_associations[name].target = value;
				return;
			}
			
			_properties[name] = value;
			
			var aggregate:Aggregate = _description.getAggregateForProperty(name);
			if (aggregate != null && aggregate.property != name.toString()) {
				aggregate.setValue(this, name, value);
				return;
			}
		}
		
		/**
		 * @inheritDoc
		 */
		public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false):void
		{
			_dispatcher.addEventListener(type, listener, useCapture, priority, useWeakReference);
		}
		
		/**
		 * @inheritDoc
		 */
		public function dispatchEvent(event:Event):Boolean
		{
			return _dispatcher.dispatchEvent(event);
		}
		
		/**
		 * @inheritDoc
		 */
		public function hasEventListener(type:String):Boolean
		{
			return _dispatcher.hasEventListener(type);
		}
		
		/**
		 * @inheritDoc
		 */
		public function removeEventListener(type:String, listener:Function, useCapture:Boolean = false):void
		{
			_dispatcher.removeEventListener(type, listener, useCapture);
		}
		
		/**
		 * @inheritDoc
		 */
		public function willTrigger(type:String):Boolean
		{
			return _dispatcher.willTrigger(type);
		}
	}
}

import mesh.Entity;
import mesh.EntityDescription;
import mesh.Properties;
import mesh.associations.AssociationProxy;
import mesh.associations.Relationship;

import operations.ParallelOperation;

class SaveEntityRelationshipsOperation extends ParallelOperation
{
	public function SaveEntityRelationshipsOperation(associations:Object)
	{
		super(generateOperations(associations));
	}
	
	private function generateOperations(associations:Object):Array
	{
		var tempOperations:Array = [];
		for (var property:String in associations) {
			tempOperations.push(associations[property].save(true, false));
		}
		return tempOperations;
	}
}
