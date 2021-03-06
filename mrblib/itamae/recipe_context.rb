module Itamae
  class RecipeContext
    NotFoundError = Class.new(StandardError)

    def initialize(recipe, variables = {})
      @recipe = recipe
      @variables = variables
      @variables.each do |key, value|
        if value.is_a?(Proc)
          define_singleton_method(key, &value)
        else
          define_singleton_method(key) { value }
        end
      end
    end

    def directory(path, &block)
      @recipe.children << Resource::Directory.new(path, @recipe, @variables, &block)
    end

    def execute(command, &block)
      @recipe.children << Resource::Execute.new(command, @recipe, @variables, &block)
    end

    def file(path, &block)
      @recipe.children << Resource::File.new(path, @recipe, @variables, &block)
    end

    def gem_package(package_name, &block)
      @recipe.children << Resource::GemPackage.new(package_name, @recipe, @variables, &block)
    end

    def git(destination, &block)
      @recipe.children << Resource::Git.new(destination, @recipe, @variables, &block)
    end

    def link(link_path, &block)
      @recipe.children << Resource::Link.new(link_path, @recipe, @variables, &block)
    end

    def package(name, &block)
      @recipe.children << Resource::Package.new(name, @recipe, @variables, &block)
    end

    def remote_file(path, &block)
      @recipe.children << Resource::RemoteFile.new(path, @recipe, @variables, &block).tap do |r|
        r.recipe_dir = File.dirname(@recipe.path)
      end
    end

    def service(name, &block)
      @recipe.children << Resource::Service.new(name, @recipe, @variables, &block)
    end

    def template(path, &block)
      @recipe.children << Resource::Template.new(path, @recipe, @variables, &block).tap do |r|
        r.recipe_dir = File.dirname(@recipe.path)
        r.node = @variables[:node]
      end
    end

    def define(name, params = {}, &block)
      klass = Resource::Definition.create_class(name, params)
      RecipeContext.send(:define_method, name) do |n, &b|
        @recipe.children << RecipeFromDefinition.new(name, n).tap do |recipe|
          params = klass.new(n, @recipe, @variables, &b).attributes.merge(name: n)
          RecipeContext.new(recipe, @variables.merge(params: params)).instance_exec(&block)
        end
      end
    end

    def include_recipe(target)
      path = ::File.expand_path(target, File.dirname(@recipe.path))
      path = ::File.join(path, 'default.rb') if ::Dir.exists?(path)
      path.concat('.rb') unless path.end_with?('.rb')

      unless File.exist?(path)
        raise NotFoundError, "Recipe not found. (#{target})"
      end

      if @recipe.children.find { |r| r.is_a?(Recipe) && r.path == path }
        Itamae.logger.debug "Recipe, #{path}, is skipped because it is already included"
        return
      end

      @recipe.children << Recipe.new(path).tap do |recipe|
        RecipeContext.new(recipe, @variables).instance_eval(File.read(path), path, 1)
      end
    end
  end
end
