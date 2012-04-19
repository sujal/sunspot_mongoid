require 'sunspot'
require 'mongoid'
require 'sunspot/rails'

# == Examples:
#
# class Post
#   include Mongoid::Document
#   field :title
# 
#   include Sunspot::Mongoid
#   searchable do
#     text :title
#   end
# end
#
module Sunspot
  module Mongoid
    def self.included(base)
      base.class_eval do
        extend Sunspot::Rails::Searchable::ActsAsMethods
        extend Sunspot::Mongoid::ActsAsMethods
        Sunspot::Adapters::DataAccessor.register(DataAccessor, base)
        Sunspot::Adapters::InstanceAdapter.register(InstanceAdapter, base)
        after_destroy :_remove_index
        after_save :_update_index
      end
    end

    module ActsAsMethods
      # ClassMethods isn't loaded until searchable is called so we need
      # call it, then extend our own ClassMethods.
      def searchable (opt = {}, &block)
        super
        extend ClassMethods
      end
    end

    module ClassMethods
      # The sunspot solr_index method is very dependent on ActiveRecord, so
      # we'll change it to work more efficiently with Mongoid.
      def solr_index(opts={})
        batch_size = opts[:batch_size] || Sunspot.config.indexing.default_batch_size
        0.step(count, batch_size) do |offset|
          Sunspot.index(limit(batch_size).skip(offset))
        end
        Sunspot.commit
      end

      def solr_index_orphans(opts={})
        batch_size = opts[:batch_size] || Sunspot.config.indexing.default_batch_size
        count = self.count
        indexed_ids = solr_search_ids { paginate(:page => 1, :per_page => count) }.to_set
        only(:id).each do |object|
          indexed_ids.delete(object.id)
        end
        indexed_ids.to_a
      end
    end


    class InstanceAdapter < Sunspot::Adapters::InstanceAdapter
      def id
        @instance.id.to_s
      end
    end

    class DataAccessor < Sunspot::Adapters::DataAccessor
      def load(id)
        criteria(id).first
      end

      def load_all(ids)
        criteria(ids)
      end

      private

      def criteria(id)
        c = @clazz.criteria
        c.respond_to?(:for_ids) ? c.for_ids(ids) : c.id(ids)
      end
    end
    def _remove_index
      Sunspot.remove! self
    end
    def _update_index
      Sunspot.index! self
    end
  end
end
